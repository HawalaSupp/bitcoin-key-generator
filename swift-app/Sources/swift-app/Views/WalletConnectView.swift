import SwiftUI
#if os(macOS)
import AppKit
#endif

// MARK: - WalletConnect View

struct WalletConnectView: View {
    @StateObject private var service = WalletConnectService()
    @Environment(\.dismiss) private var dismiss
    
    @State private var wcUri: String = ""
    @State private var showScanner = false
    @State private var showingProposal = false
    @State private var showingRequest = false
    @State private var selectedAccount: String = ""
    
    // Available accounts from wallet
    var availableAccounts: [String]
    var onSign: (WCSessionRequest) async throws -> String
    
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    // Header
                    headerSection
                    
                    // Connect new dApp
                    connectSection
                    
                    // Active sessions
                    if !service.sessions.isEmpty {
                        sessionsSection
                    }
                    
                    Spacer(minLength: 40)
                }
                .padding(20)
            }
            .background(Color(nsColor: .windowBackgroundColor))
            .navigationTitle("WalletConnect")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
        .frame(minWidth: 500, minHeight: 600)
        .sheet(isPresented: $showingProposal) {
            if let proposal = service.pendingProposal {
                SessionProposalSheet(
                    proposal: proposal,
                    availableAccounts: availableAccounts,
                    onApprove: { accounts in
                        Task {
                            try? await service.approveSession(proposal: proposal, accounts: accounts)
                        }
                        showingProposal = false
                    },
                    onReject: {
                        Task {
                            try? await service.rejectSession(proposal: proposal)
                        }
                        showingProposal = false
                    }
                )
            }
        }
        .sheet(isPresented: $showingRequest) {
            if let request = service.pendingRequest {
                SessionRequestSheet(
                    request: request,
                    session: service.sessions.first { $0.topic == request.topic },
                    onApprove: {
                        Task {
                            do {
                                let result = try await onSign(request)
                                try await service.approveRequest(request: request, result: result)
                            } catch {
                                try? await service.rejectRequest(request: request, reason: error.localizedDescription)
                            }
                        }
                        showingRequest = false
                    },
                    onReject: {
                        Task {
                            try? await service.rejectRequest(request: request)
                        }
                        showingRequest = false
                    }
                )
            }
        }
        .onChange(of: service.pendingProposal) { proposal in
            showingProposal = proposal != nil
        }
        .onChange(of: service.pendingRequest) { request in
            showingRequest = request != nil
        }
    }
    
    // MARK: - Header
    
    private var headerSection: some View {
        VStack(spacing: 12) {
            Image(systemName: "link.circle.fill")
                .font(.system(size: 48))
                .foregroundStyle(.blue)
            
            Text("Connect to dApps")
                .font(.title2)
                .fontWeight(.semibold)
            
            Text("Scan a WalletConnect QR code or paste a connection URI to connect your wallet to decentralized applications.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(.vertical, 8)
    }
    
    // MARK: - Connect Section
    
    private var connectSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("New Connection")
                .font(.headline)
            
            VStack(spacing: 12) {
                // URI Input
                HStack(spacing: 8) {
                    TextField("wc:...", text: $wcUri)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(.body, design: .monospaced))
                    
                    Button {
                        pasteFromClipboard()
                    } label: {
                        Image(systemName: "doc.on.clipboard")
                    }
                    .buttonStyle(.bordered)
                    .help("Paste from clipboard")
                }
                
                // Action buttons
                HStack(spacing: 12) {
                    Button {
                        showScanner = true
                    } label: {
                        Label("Scan QR", systemImage: "qrcode.viewfinder")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .disabled(true) // QR scanning not yet implemented
                    
                    Button {
                        Task {
                            await connect()
                        }
                    } label: {
                        Label("Connect", systemImage: "link")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(wcUri.isEmpty || service.isConnecting)
                }
                
                // Status
                if service.isConnecting {
                    HStack(spacing: 8) {
                        ProgressView()
                            .controlSize(.small)
                        Text("Connecting...")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                
                if let error = service.connectionError {
                    Label(error, systemImage: "exclamationmark.triangle")
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            }
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color(nsColor: .controlBackgroundColor))
            )
        }
    }
    
    // MARK: - Sessions Section
    
    private var sessionsSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("Active Sessions")
                    .font(.headline)
                
                Spacer()
                
                Text("\(service.sessions.count)")
                    .font(.caption)
                    .fontWeight(.medium)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.blue.opacity(0.15))
                    .foregroundStyle(.blue)
                    .clipShape(Capsule())
            }
            
            VStack(spacing: 0) {
                ForEach(service.sessions) { session in
                    SessionRow(
                        session: session,
                        onDisconnect: {
                            Task {
                                try? await service.disconnect(session: session)
                            }
                        }
                    )
                    
                    if session.id != service.sessions.last?.id {
                        Divider()
                            .padding(.horizontal)
                    }
                }
            }
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color(nsColor: .controlBackgroundColor))
            )
        }
    }
    
    // MARK: - Actions
    
    private func pasteFromClipboard() {
        #if os(macOS)
        if let string = NSPasteboard.general.string(forType: .string) {
            wcUri = string.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        #endif
    }
    
    private func connect() async {
        do {
            try await service.pair(uri: wcUri)
            wcUri = ""
        } catch {
            // Error is displayed via service.connectionError
        }
    }
}

// MARK: - Session Row

private struct SessionRow: View {
    let session: WCSession
    let onDisconnect: () -> Void
    
    @State private var isHovered = false
    
    var body: some View {
        HStack(spacing: 12) {
            // Icon
            AsyncImage(url: session.peer.iconURL) { image in
                image
                    .resizable()
                    .aspectRatio(contentMode: .fit)
            } placeholder: {
                Image(systemName: "app.fill")
                    .font(.title2)
                    .foregroundStyle(.secondary)
            }
            .frame(width: 40, height: 40)
            .clipShape(RoundedRectangle(cornerRadius: 8))
            
            // Info
            VStack(alignment: .leading, spacing: 2) {
                Text(session.peer.name)
                    .font(.subheadline)
                    .fontWeight(.medium)
                
                Text(session.peer.url)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                
                HStack(spacing: 4) {
                    ForEach(session.chains.prefix(3), id: \.self) { chain in
                        Text(chainName(for: chain))
                            .font(.caption2)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.blue.opacity(0.1))
                            .foregroundStyle(.blue)
                            .clipShape(Capsule())
                    }
                    
                    if session.chains.count > 3 {
                        Text("+\(session.chains.count - 3)")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            
            Spacer()
            
            // Disconnect button
            Button(role: .destructive) {
                onDisconnect()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.title3)
            }
            .buttonStyle(.plain)
            .opacity(isHovered ? 1 : 0.5)
        }
        .padding(12)
        .background(isHovered ? Color.primary.opacity(0.03) : Color.clear)
        .onHover { hovering in
            isHovered = hovering
        }
    }
    
    private func chainName(for chainId: String) -> String {
        WalletConnectService.supportedChains.first { $0.id == chainId }?.name ?? chainId
    }
}

// MARK: - Session Proposal Sheet

private struct SessionProposalSheet: View {
    let proposal: WCSessionProposal
    let availableAccounts: [String]
    let onApprove: ([String]) -> Void
    let onReject: () -> Void
    
    @State private var selectedAccounts: Set<String> = []
    
    var body: some View {
        VStack(spacing: 24) {
            // Header
            VStack(spacing: 12) {
                AsyncImage(url: proposal.proposer.iconURL) { image in
                    image
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                } placeholder: {
                    Image(systemName: "app.fill")
                        .font(.system(size: 40))
                        .foregroundStyle(.secondary)
                }
                .frame(width: 64, height: 64)
                .clipShape(RoundedRectangle(cornerRadius: 12))
                
                Text(proposal.proposer.name)
                    .font(.title2)
                    .fontWeight(.semibold)
                
                Text(proposal.proposer.url)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                
                Text("wants to connect to your wallet")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            
            // Permissions
            VStack(alignment: .leading, spacing: 12) {
                Text("Permissions Requested")
                    .font(.headline)
                
                VStack(alignment: .leading, spacing: 8) {
                    PermissionRow(icon: "eye", text: "View your wallet addresses")
                    PermissionRow(icon: "square.and.arrow.up", text: "Request transaction signatures")
                    PermissionRow(icon: "signature", text: "Request message signatures")
                }
                .padding()
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color.orange.opacity(0.1))
                )
            }
            
            // Account selection
            if availableAccounts.count > 1 {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Select Accounts")
                        .font(.headline)
                    
                    ForEach(availableAccounts, id: \.self) { account in
                        Button {
                            if selectedAccounts.contains(account) {
                                selectedAccounts.remove(account)
                            } else {
                                selectedAccounts.insert(account)
                            }
                        } label: {
                            HStack {
                                Image(systemName: selectedAccounts.contains(account) ? "checkmark.circle.fill" : "circle")
                                    .foregroundStyle(selectedAccounts.contains(account) ? .blue : .secondary)
                                
                                Text("\(account.prefix(6))...\(account.suffix(4))")
                                    .font(.system(.body, design: .monospaced))
                                
                                Spacer()
                            }
                            .padding(12)
                            .background(
                                RoundedRectangle(cornerRadius: 8)
                                    .fill(Color(nsColor: .controlBackgroundColor))
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            
            // Actions
            HStack(spacing: 12) {
                Button("Reject") {
                    onReject()
                }
                .buttonStyle(.bordered)
                .frame(maxWidth: .infinity)
                
                Button("Connect") {
                    let accounts = selectedAccounts.isEmpty ? availableAccounts : Array(selectedAccounts)
                    onApprove(accounts)
                }
                .buttonStyle(.borderedProminent)
                .frame(maxWidth: .infinity)
            }
        }
        .padding(24)
        .frame(width: 400)
        .onAppear {
            if availableAccounts.count == 1 {
                selectedAccounts = Set(availableAccounts)
            }
        }
    }
}

private struct PermissionRow: View {
    let icon: String
    let text: String
    
    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.caption)
                .foregroundStyle(.orange)
            
            Text(text)
                .font(.subheadline)
        }
    }
}

// MARK: - Session Request Sheet

private struct SessionRequestSheet: View {
    let request: WCSessionRequest
    let session: WCSession?
    let onApprove: () -> Void
    let onReject: () -> Void
    
    var body: some View {
        VStack(spacing: 24) {
            // Header
            VStack(spacing: 12) {
                if let session = session {
                    AsyncImage(url: session.peer.iconURL) { image in
                        image
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                    } placeholder: {
                        Image(systemName: "app.fill")
                            .font(.system(size: 40))
                            .foregroundStyle(.secondary)
                    }
                    .frame(width: 48, height: 48)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                    
                    Text(session.peer.name)
                        .font(.headline)
                }
                
                Text(request.methodDisplay)
                    .font(.title2)
                    .fontWeight(.semibold)
            }
            
            // Request details
            VStack(alignment: .leading, spacing: 12) {
                DetailItem(label: "Method", value: request.method)
                DetailItem(label: "Chain", value: request.chainId)
                
                if let params = request.params {
                    Text("Parameters")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    
                    ScrollView {
                        Text(formatParams(params))
                            .font(.system(.caption, design: .monospaced))
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .frame(height: 150)
                    .padding(8)
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(Color(nsColor: .controlBackgroundColor))
                    )
                }
            }
            
            // Warning for certain operations
            if isRiskyOperation {
                HStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                    
                    Text("Review carefully before approving")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
                .padding(12)
                .frame(maxWidth: .infinity)
                .background(Color.orange.opacity(0.1))
                .clipShape(RoundedRectangle(cornerRadius: 8))
            }
            
            // Actions
            HStack(spacing: 12) {
                Button("Reject") {
                    onReject()
                }
                .buttonStyle(.bordered)
                .frame(maxWidth: .infinity)
                
                Button("Approve") {
                    onApprove()
                }
                .buttonStyle(.borderedProminent)
                .frame(maxWidth: .infinity)
            }
        }
        .padding(24)
        .frame(width: 450)
    }
    
    private var isRiskyOperation: Bool {
        request.method.contains("sendTransaction") || request.method.contains("sign")
    }
    
    private func formatParams(_ params: Any) -> String {
        if let data = try? JSONSerialization.data(withJSONObject: params, options: .prettyPrinted),
           let string = String(data: data, encoding: .utf8) {
            return string
        }
        return String(describing: params)
    }
}

private struct DetailItem: View {
    let label: String
    let value: String
    
    var body: some View {
        HStack {
            Text(label)
                .font(.subheadline)
                .foregroundStyle(.secondary)
            
            Spacer()
            
            Text(value)
                .font(.system(.subheadline, design: .monospaced))
        }
    }
}

// MARK: - Preview

#Preview {
    WalletConnectView(
        availableAccounts: ["0x742d35Cc6634C0532925a3b844Bc9e7595f2b4F6"],
        onSign: { _ in "" }
    )
}
