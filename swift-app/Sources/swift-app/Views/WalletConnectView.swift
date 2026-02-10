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
                        Text("Connecting to dApp…")
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
                HStack(spacing: 4) {
                    Text(session.peer.name)
                        .font(.subheadline)
                        .fontWeight(.medium)
                    
                    // Verification badge
                    switch DAppRegistry.shared.verify(peer: session.peer) {
                    case .verified:
                        Image(systemName: "checkmark.seal.fill")
                            .font(.caption2)
                            .foregroundStyle(.green)
                    case .suspicious:
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.caption2)
                            .foregroundStyle(.red)
                    case .unknown:
                        EmptyView()
                    }
                }
                
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
    
    private var verificationStatus: DAppRegistry.VerificationStatus {
        DAppRegistry.shared.verify(peer: proposal.proposer)
    }
    
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
                
                HStack(spacing: 6) {
                    Text(proposal.proposer.name)
                        .font(.title2)
                        .fontWeight(.semibold)
                    
                    // Verification badge
                    verificationBadge
                }
                
                Text(proposal.proposer.url)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                
                Text("wants to connect to your wallet")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            
            // Verification status banner
            verificationBanner
            
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
    
    // MARK: - Verification Badge
    
    @ViewBuilder
    private var verificationBadge: some View {
        switch verificationStatus {
        case .verified:
            Image(systemName: "checkmark.seal.fill")
                .foregroundStyle(.green)
                .help("Verified dApp")
        case .suspicious:
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.red)
                .help("Suspicious dApp")
        case .unknown:
            Image(systemName: "questionmark.circle")
                .foregroundStyle(.secondary)
                .help("Unverified dApp")
        }
    }
    
    // MARK: - Verification Banner
    
    @ViewBuilder
    private var verificationBanner: some View {
        switch verificationStatus {
        case .verified(let info):
            HStack(spacing: 8) {
                Image(systemName: "checkmark.seal.fill")
                    .foregroundStyle(.green)
                Text("Verified: \(info.name) — \(info.category.rawValue)")
                    .font(.caption)
                    .foregroundStyle(.green)
            }
            .padding(10)
            .frame(maxWidth: .infinity)
            .background(Color.green.opacity(0.1))
            .clipShape(RoundedRectangle(cornerRadius: 8))
        case .suspicious(let reason):
            HStack(spacing: 8) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.red)
                VStack(alignment: .leading, spacing: 2) {
                    Text("⚠️ Suspicious dApp")
                        .font(.caption)
                        .fontWeight(.semibold)
                        .foregroundStyle(.red)
                    Text(reason)
                        .font(.caption2)
                        .foregroundStyle(.red.opacity(0.8))
                }
            }
            .padding(10)
            .frame(maxWidth: .infinity)
            .background(Color.red.opacity(0.1))
            .clipShape(RoundedRectangle(cornerRadius: 8))
        case .unknown:
            HStack(spacing: 8) {
                Image(systemName: "info.circle")
                    .foregroundStyle(.orange)
                Text("This dApp is not in our verified registry. Proceed with caution.")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
            .padding(10)
            .frame(maxWidth: .infinity)
            .background(Color.orange.opacity(0.1))
            .clipShape(RoundedRectangle(cornerRadius: 8))
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
    
    @State private var decodedTx: DecodedTransaction?
    @State private var parsedTypedData: EIP712TypedData?
    @State private var decodedPersonalMessage: String?
    
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
                
                // Decoded transaction view
                if let decoded = decodedTx {
                    decodedTransactionSection(decoded)
                }
                
                // Decoded EIP-712 typed data
                if let typedData = parsedTypedData {
                    eip712Section(typedData)
                }
                
                // Decoded personal message
                if let message = decodedPersonalMessage {
                    personalMessageSection(message)
                }
                
                // Fallback: raw params if nothing decoded
                if decodedTx == nil && parsedTypedData == nil && decodedPersonalMessage == nil,
                   let params = request.params {
                    rawParamsSection(params)
                }
            }
            
            // Risk warnings
            warningSection
            
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
                .disabled(decodedTx?.riskLevel == .critical)
            }
        }
        .padding(24)
        .frame(width: 450)
        .onAppear { decodeRequest() }
    }
    
    // MARK: - Decoded Transaction Section
    
    @ViewBuilder
    private func decodedTransactionSection(_ decoded: DecodedTransaction) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Transaction Details", systemImage: "doc.text.magnifyingglass")
                .font(.subheadline)
                .fontWeight(.semibold)
            
            VStack(alignment: .leading, spacing: 6) {
                // Method name + description
                HStack(spacing: 6) {
                    Text(decoded.methodName)
                        .font(.system(.caption, design: .monospaced))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.blue.opacity(0.15))
                        .foregroundStyle(.blue)
                        .clipShape(Capsule())
                    
                    Text(decoded.methodDescription)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                
                // Human-readable summary
                Text(decoded.humanReadable)
                    .font(.subheadline)
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(Color(nsColor: .controlBackgroundColor))
                    )
                
                // Contract info
                if let contractName = decoded.contractName {
                    HStack(spacing: 4) {
                        if decoded.isVerified {
                            Image(systemName: "checkmark.seal.fill")
                                .foregroundStyle(.green)
                                .font(.caption)
                        }
                        Text("Contract: \(contractName)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                
                // Native value
                if let value = decoded.nativeValue, value != "0" {
                    DetailItem(label: "Value", value: "\(value) ETH")
                }
                
                // Decoded parameters
                if !decoded.decodedParams.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Parameters")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        
                        ForEach(Array(decoded.decodedParams.keys.sorted()), id: \.self) { key in
                            HStack {
                                Text(key)
                                    .font(.system(.caption2, design: .monospaced))
                                    .foregroundStyle(.secondary)
                                Spacer()
                                Text(String(describing: decoded.decodedParams[key] ?? ""))
                                    .font(.system(.caption2, design: .monospaced))
                                    .lineLimit(1)
                                    .truncationMode(.middle)
                            }
                        }
                    }
                    .padding(8)
                    .background(
                        RoundedRectangle(cornerRadius: 6)
                            .fill(Color(nsColor: .controlBackgroundColor))
                    )
                }
            }
        }
    }
    
    // MARK: - EIP-712 Section
    
    @ViewBuilder
    private func eip712Section(_ typedData: EIP712TypedData) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("EIP-712 Typed Data", systemImage: "signature")
                .font(.subheadline)
                .fontWeight(.semibold)
            
            VStack(alignment: .leading, spacing: 8) {
                // Domain
                VStack(alignment: .leading, spacing: 4) {
                    Text("Domain")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fontWeight(.medium)
                    
                    if let name = typedData.domain.name {
                        eip712Row("Name", name)
                    }
                    if let version = typedData.domain.version {
                        eip712Row("Version", version)
                    }
                    if let chainId = typedData.domain.chainId {
                        switch chainId {
                        case .number(let n):
                            eip712Row("Chain ID", "\(n)")
                        case .string(let s):
                            eip712Row("Chain ID", s)
                        }
                    }
                    if let contract = typedData.domain.verifyingContract {
                        eip712Row("Contract", contract)
                    }
                }
                .padding(8)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(Color(nsColor: .controlBackgroundColor))
                )
                
                // Primary Type
                HStack {
                    Text("Primary Type")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text(typedData.primaryType)
                        .font(.system(.caption, design: .monospaced))
                }
                
                // Message fields
                VStack(alignment: .leading, spacing: 4) {
                    Text("Message")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fontWeight(.medium)
                    
                    ForEach(Array(typedData.message.keys.sorted()), id: \.self) { key in
                        if let value = typedData.message[key] {
                            eip712Row(key, formatAnyCodable(value))
                        }
                    }
                }
                .padding(8)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(Color(nsColor: .controlBackgroundColor))
                )
            }
        }
    }
    
    @ViewBuilder
    private func eip712Row(_ label: String, _ value: String) -> some View {
        HStack(alignment: .top) {
            Text(label)
                .font(.system(.caption2, design: .monospaced))
                .foregroundStyle(.secondary)
                .frame(minWidth: 60, alignment: .leading)
            Text(value)
                .font(.system(.caption2, design: .monospaced))
                .lineLimit(2)
                .truncationMode(.middle)
        }
    }
    
    private func formatAnyCodable(_ codable: AnyCodable) -> String {
        let val = codable.value
        if let str = val as? String { return str }
        if let num = val as? Int { return "\(num)" }
        if let num = val as? Double { return "\(num)" }
        if let bool = val as? Bool { return bool ? "true" : "false" }
        if let data = try? JSONSerialization.data(withJSONObject: val, options: []),
           let str = String(data: data, encoding: .utf8) { return str }
        return String(describing: val)
    }
    
    // MARK: - Personal Message Section
    
    @ViewBuilder
    private func personalMessageSection(_ message: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Message to Sign", systemImage: "text.bubble")
                .font(.subheadline)
                .fontWeight(.semibold)
            
            ScrollView {
                Text(message)
                    .font(.system(.caption, design: .monospaced))
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxHeight: 120)
            .padding(10)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color(nsColor: .controlBackgroundColor))
            )
        }
    }
    
    // MARK: - Raw Params Fallback
    
    @ViewBuilder
    private func rawParamsSection(_ params: Any) -> some View {
        VStack(alignment: .leading, spacing: 8) {
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
    
    // MARK: - Warning Section
    
    @ViewBuilder
    private var warningSection: some View {
        if let decoded = decodedTx {
            // Show decoded warnings + risk level
            VStack(spacing: 8) {
                if decoded.riskLevel == .critical || decoded.riskLevel == .high {
                    HStack(spacing: 8) {
                        Image(systemName: decoded.riskLevel == .critical ? "xmark.octagon.fill" : "exclamationmark.triangle.fill")
                            .foregroundStyle(decoded.riskLevel == .critical ? .red : .orange)
                        
                        Text(decoded.riskLevel == .critical ? "CRITICAL RISK — This transaction is dangerous" : "HIGH RISK — Review carefully")
                            .font(.caption)
                            .fontWeight(.semibold)
                            .foregroundStyle(decoded.riskLevel == .critical ? .red : .orange)
                    }
                    .padding(12)
                    .frame(maxWidth: .infinity)
                    .background((decoded.riskLevel == .critical ? Color.red : Color.orange).opacity(0.1))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                }
                
                ForEach(decoded.warnings, id: \.self) { warning in
                    HStack(spacing: 6) {
                        Text(warning.icon)
                            .font(.caption2)
                        Text(warning.rawValue)
                            .font(.caption2)
                            .foregroundStyle(.orange)
                    }
                }
            }
        } else if isRiskyOperation {
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
    }
    
    // MARK: - Decode Logic
    
    private func decodeRequest() {
        switch request.method {
        case "eth_sendTransaction", "eth_signTransaction":
            decodeTransaction()
        case "eth_signTypedData", "eth_signTypedData_v3", "eth_signTypedData_v4":
            decodeTypedData()
        case "personal_sign", "eth_sign":
            decodePersonalSign()
        default:
            break
        }
    }
    
    private func decodeTransaction() {
        guard let params = request.params as? [[String: Any]],
              let txParams = params.first else { return }
        
        let data = txParams["data"] as? String ?? "0x"
        let to = txParams["to"] as? String
        let value = txParams["value"] as? String
        
        decodedTx = TransactionDecoder.shared.decode(data: data, to: to, value: value)
    }
    
    private func decodeTypedData() {
        guard let params = request.params as? [Any],
              params.count >= 2 else { return }
        
        let jsonStr: String?
        if let str = params[1] as? String {
            jsonStr = str
        } else if let dict = params[1] as? [String: Any],
                  let jsonData = try? JSONSerialization.data(withJSONObject: dict),
                  let str = String(data: jsonData, encoding: .utf8) {
            jsonStr = str
        } else {
            jsonStr = nil
        }
        
        if let json = jsonStr {
            parsedTypedData = try? EIP712TypedData.fromJSON(json)
        }
    }
    
    private func decodePersonalSign() {
        guard let params = request.params as? [Any],
              params.count >= 2,
              let hexMsg = params[1] as? String else { return }
        
        // Try decoding hex to UTF-8
        if hexMsg.hasPrefix("0x") {
            let hex = String(hexMsg.dropFirst(2))
            if let data = Data(hexString: hex), let text = String(data: data, encoding: .utf8) {
                decodedPersonalMessage = text
                return
            }
        }
        decodedPersonalMessage = hexMsg
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

#if false // Disabled #Preview for command-line builds
#if false
#if false
#Preview {
    WalletConnectView(
        availableAccounts: ["0x742d35Cc6634C0532925a3b844Bc9e7595f2b4F6"],
        onSign: { _ in "" }
    )
}
#endif
#endif
#endif
