//
//  HardwareWalletSigningSheet.swift
//  Hawala
//
//  Hardware Wallet Signing Flow
//
//  Displays transaction details and guides users through
//  confirming transactions on their hardware wallet.
//

import SwiftUI

// MARK: - Signing Sheet

/// Sheet for signing transactions with hardware wallet
struct HardwareWalletSigningSheet: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var viewModel: HardwareWalletSigningViewModel
    
    init(
        account: HardwareWalletAccount,
        transaction: HardwareWalletTransaction,
        chain: SupportedChain,
        onSigned: @escaping (SignatureResult) -> Void,
        onError: @escaping (Error) -> Void
    ) {
        _viewModel = StateObject(wrappedValue: HardwareWalletSigningViewModel(
            account: account,
            transaction: transaction,
            chain: chain,
            onSigned: onSigned,
            onError: onError
        ))
    }
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                switch viewModel.state {
                case .connecting:
                    ConnectingStateView(viewModel: viewModel)
                    
                case .awaitingConfirmation:
                    AwaitingConfirmationView(viewModel: viewModel)
                    
                case .signing:
                    SigningView(viewModel: viewModel)
                    
                case .complete:
                    SigningCompleteView(dismiss: dismiss)
                    
                case .error:
                    SigningErrorView(viewModel: viewModel, dismiss: dismiss)
                }
            }
            .padding()
            .navigationTitle("Sign Transaction")
            .toolbar {
                ToolbarItemGroup(placement: .cancellationAction) {
                    Button("Cancel") {
                        viewModel.cancel()
                        dismiss()
                    }
                }
            }
        }
        .onAppear {
            viewModel.start()
        }
    }
}

// MARK: - View Model

@MainActor
class HardwareWalletSigningViewModel: ObservableObject {
    enum SigningState {
        case connecting
        case awaitingConfirmation
        case signing
        case complete
        case error
    }
    
    @Published var state: SigningState = .connecting
    @Published var statusMessage = "Connecting..."
    @Published var errorMessage: String?
    
    let account: HardwareWalletAccount
    let transaction: HardwareWalletTransaction
    let chain: SupportedChain
    
    private let onSigned: (SignatureResult) -> Void
    private let onError: (Error) -> Void
    private let manager = HardwareWalletManagerV2.shared
    private var signingTask: Task<Void, Never>?
    
    init(
        account: HardwareWalletAccount,
        transaction: HardwareWalletTransaction,
        chain: SupportedChain,
        onSigned: @escaping (SignatureResult) -> Void,
        onError: @escaping (Error) -> Void
    ) {
        self.account = account
        self.transaction = transaction
        self.chain = chain
        self.onSigned = onSigned
        self.onError = onError
    }
    
    func start() {
        signingTask = Task {
            await performSigning()
        }
    }
    
    func cancel() {
        signingTask?.cancel()
    }
    
    func retry() {
        state = .connecting
        errorMessage = nil
        start()
    }
    
    private func performSigning() async {
        // Find or connect to the device
        state = .connecting
        statusMessage = "Looking for \(account.deviceType.displayName)..."
        
        // Get discovered devices
        let devices = manager.discoveredDevices
        
        guard let device = devices.first(where: { $0.deviceType == account.deviceType }) else {
            // Start scanning and wait for device
            manager.startScanning()
            
            // Wait up to 30 seconds for device
            for _ in 0..<30 {
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                if Task.isCancelled { return }
                
                let updatedDevices = manager.discoveredDevices
                if let foundDevice = updatedDevices.first(where: { $0.deviceType == account.deviceType }) {
                    await connectAndSign(device: foundDevice)
                    return
                }
            }
            
            errorMessage = "Could not find \(account.deviceType.displayName). Please connect your device."
            state = .error
            return
        }
        
        await connectAndSign(device: device)
    }
    
    private func connectAndSign(device: DiscoveredDevice) async {
        do {
            // Connect to device
            statusMessage = "Connecting to \(device.deviceType.displayName)..."
            
            if manager.connectedWallets[device.id] == nil {
                _ = try await manager.connect(to: device)
            }
            
            // Set up callbacks
            manager.onButtonConfirmationRequired = { [weak self] message in
                Task { @MainActor in
                    self?.state = .awaitingConfirmation
                    self?.statusMessage = message
                }
            }
            
            // Request signature
            state = .awaitingConfirmation
            statusMessage = "Please review and confirm on your device"
            
            guard let path = DerivationPath(string: account.derivationPath) else {
                throw HWError.invalidPath(account.derivationPath)
            }
            
            state = .signing
            statusMessage = "Signing transaction..."
            
            let signature = try await manager.signTransaction(
                deviceId: device.id,
                path: path,
                transaction: transaction,
                chain: chain
            )
            
            state = .complete
            onSigned(signature)
            
        } catch {
            errorMessage = error.localizedDescription
            state = .error
            onError(error)
        }
    }
}

// MARK: - State Views

struct ConnectingStateView: View {
    @ObservedObject var viewModel: HardwareWalletSigningViewModel
    
    var body: some View {
        VStack(spacing: 24) {
            Spacer()
            
            ProgressView()
                .scaleEffect(1.5)
            
            Text(viewModel.statusMessage)
                .font(.headline)
            
            Text(viewModel.account.deviceType.displayName)
                .foregroundStyle(.secondary)
            
            Spacer()
        }
    }
}

struct AwaitingConfirmationView: View {
    @ObservedObject var viewModel: HardwareWalletSigningViewModel
    
    var body: some View {
        VStack(spacing: 24) {
            // Transaction preview
            if let displayInfo = viewModel.transaction.displayInfo {
                TransactionPreviewCard(info: displayInfo)
            }
            
            Spacer()
            
            // Device prompt
            VStack(spacing: 16) {
                Image(systemName: "hand.tap")
                    .font(.system(size: 48))
                    .foregroundStyle(.blue)
                
                Text("Confirm on Device")
                    .font(.headline)
                
                Text(viewModel.statusMessage)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            
            Spacer()
            
            // Device indicator
            HStack {
                Image(systemName: deviceIcon(for: viewModel.account.deviceType))
                Text(viewModel.account.deviceType.displayName)
            }
            .padding()
            .background(.ultraThinMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
    }
    
    private func deviceIcon(for type: HardwareDeviceType) -> String {
        switch type.manufacturer {
        case .ledger: return "creditcard"
        case .trezor: return "shield"
        }
    }
}

struct TransactionPreviewCard: View {
    let info: TransactionDisplayInfo
    
    var body: some View {
        VStack(spacing: 12) {
            // Header
            HStack {
                Text(info.type)
                    .font(.headline)
                Spacer()
                if let network = info.network {
                    Text(network)
                        .font(.caption)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(.blue.opacity(0.1))
                        .foregroundStyle(.blue)
                        .clipShape(Capsule())
                }
            }
            
            Divider()
            
            // Amount
            if let amount = info.amount {
                HStack {
                    Text("Amount")
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text(amount)
                        .fontWeight(.semibold)
                }
            }
            
            // Recipient
            if let recipient = info.recipient {
                HStack {
                    Text("To")
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text(truncateAddress(recipient))
                        .font(.system(.body, design: .monospaced))
                }
            }
            
            // Fee
            if let fee = info.fee {
                HStack {
                    Text("Network Fee")
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text(fee)
                }
            }
        }
        .padding()
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
    
    private func truncateAddress(_ address: String) -> String {
        guard address.count > 14 else { return address }
        return "\(address.prefix(6))...\(address.suffix(4))"
    }
}

struct SigningView: View {
    @ObservedObject var viewModel: HardwareWalletSigningViewModel
    
    var body: some View {
        VStack(spacing: 24) {
            Spacer()
            
            ProgressView()
                .scaleEffect(1.2)
            
            Text(viewModel.statusMessage)
                .font(.headline)
            
            Spacer()
        }
    }
}

struct SigningCompleteView: View {
    let dismiss: DismissAction
    
    var body: some View {
        VStack(spacing: 24) {
            Spacer()
            
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 72))
                .foregroundStyle(.green)
            
            Text("Transaction Signed")
                .font(.title2)
                .fontWeight(.bold)
            
            Text("Your transaction has been signed and is ready to broadcast.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            
            Spacer()
            
            Button("Done") {
                dismiss()
            }
            .buttonStyle(.borderedProminent)
        }
    }
}

struct SigningErrorView: View {
    @ObservedObject var viewModel: HardwareWalletSigningViewModel
    let dismiss: DismissAction
    
    var body: some View {
        VStack(spacing: 24) {
            Spacer()
            
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 64))
                .foregroundStyle(.red)
            
            Text("Signing Failed")
                .font(.headline)
            
            Text(viewModel.errorMessage ?? "An unknown error occurred")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
            
            Spacer()
            
            VStack(spacing: 12) {
                Button("Try Again") {
                    viewModel.retry()
                }
                .buttonStyle(.borderedProminent)
                
                Button("Cancel") {
                    dismiss()
                }
                .buttonStyle(.bordered)
            }
        }
    }
}

// MARK: - Preview

#Preview {
    let account = HardwareWalletAccount(
        deviceType: .ledgerNanoX,
        chain: .ethereum,
        derivationPath: "m/44'/60'/0'/0/0",
        address: "0x742d35Cc6634C0532925a3b844Bc9e7595f",
        publicKey: ""
    )
    
    let tx = HardwareWalletTransaction(
        rawData: Data(),
        displayInfo: TransactionDisplayInfo(
            type: "Send",
            amount: "0.1 ETH",
            recipient: "0x1234...abcd",
            fee: "0.002 ETH",
            network: "Ethereum"
        )
    )
    
    return HardwareWalletSigningSheet(
        account: account,
        transaction: tx,
        chain: .ethereum,
        onSigned: { _ in },
        onError: { _ in }
    )
}
