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

    enum ErrorCategory {
        case rejected
        case timeout
        case disconnected
        case mismatch
        case wrongApp
        case unavailable
        case generic
    }
    
    @Published var state: SigningState = .connecting
    @Published var statusMessage = "Connecting..."
    @Published var errorMessage: String?
    @Published var errorCategory: ErrorCategory = .generic
    
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
        // ROADMAP-22: Track signing request
        AnalyticsService.shared.track(AnalyticsService.EventName.hwSigningRequested, properties: [
            "device_type": account.deviceType.rawValue,
            "tx_type": transaction.displayInfo?.type ?? "unknown"
        ])
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
        errorCategory = .generic
        start()
    }
    
    private func performSigning() async {
        state = .connecting
        statusMessage = "Looking for \(account.deviceType.displayName)..."

        do {
            let device = try await manager.connectToSavedAccount(account)
            await connectAndSign(device: device)
        } catch is CancellationError {
            return
        } catch {
            errorMessage = error.localizedDescription
            errorCategory = categorize(error)
            statusMessage = recoveryMessage(for: error)
            state = .error
        }
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

            state = .awaitingConfirmation
            statusMessage = "Verify the signing address on your device"

            _ = try await manager.verifySavedAccount(
                deviceId: device.id,
                account: account,
                requestedChain: chain,
                verifyOnDevice: true
            )
            
            state = .awaitingConfirmation
            statusMessage = "Address verified. Review the transaction on your device"

            state = .signing
            statusMessage = "Signing transaction..."
            
            let signature = try await manager.signTransaction(
                deviceId: device.id,
                path: path,
                transaction: transaction,
                chain: chain
            )
            
            state = .complete
            // ROADMAP-22: Track signing confirmed
            AnalyticsService.shared.track(AnalyticsService.EventName.hwSigningConfirmed, properties: [
                "device_type": account.deviceType.rawValue
            ])
            onSigned(signature)
            
        } catch {
            errorMessage = error.localizedDescription
            errorCategory = categorize(error)
            statusMessage = recoveryMessage(for: error)
            state = .error
            // ROADMAP-22: Track signing rejection/failure
            let isRejection = (error as? HWError) == nil ? false : {
                if case .userRejected = error as! HWError { return true }
                return false
            }()
            AnalyticsService.shared.track(
                isRejection ? AnalyticsService.EventName.hwSigningRejected : AnalyticsService.EventName.hwPairingFailed,
                properties: [
                    "device_type": account.deviceType.rawValue,
                    "error": error.localizedDescription
                ]
            )
            onError(error)
        }
    }

    private func categorize(_ error: Error) -> ErrorCategory {
        guard let hwError = error as? HWError else {
            return .generic
        }

        switch hwError {
        case .userRejected:
            return .rejected
        case .timeout:
            return .timeout
        case .deviceDisconnected, .deviceNotFound:
            return .disconnected
        case .savedAccountMismatch, .accountChainMismatch:
            return .mismatch
        case .appNotOpen, .wrongApp, .invalidPath:
            return .wrongApp
        case .unsupportedChain, .unsupportedOperation:
            return .unavailable
        default:
            return .generic
        }
    }

    private func recoveryMessage(for error: Error) -> String {
        guard let hwError = error as? HWError else {
            return "Reconnect the device and try signing again."
        }

        switch hwError {
        case .appNotOpen(let appName):
            return "Open the \(appName) app on your \(account.deviceType.displayName), then try again."
        case .wrongApp(let expected, let current):
            return "\(account.deviceType.displayName) currently has \(current) open. Switch to \(expected) and retry."
        case .unsupportedChain:
            return "This hardware wallet flow does not support \(chain.rawValue) yet. Use a supported chain or a software signing path."
        case .invalidPath(let path):
            return "The derivation path \(path) is invalid for this account. Reconnect the account with the correct path."
        case .accountChainMismatch(let expected, let requested):
            return "This saved hardware account is for \(expected). Select a \(requested) hardware account before signing."
        case .savedAccountMismatch(_, _, let path):
            return "The connected device produced a different address for \(path). Open the correct app, verify the account, or reconnect the device with the right derivation path before signing."
        case .deviceNotFound, .deviceDisconnected:
            return "Reconnect your device and make sure Hawala can still see it before retrying."
        case .timeout:
            return "Keep the device unlocked, confirm on-device promptly, and retry."
        default:
            return "Review the transaction on device, make sure the correct app is open, and retry."
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
            
            Image(systemName: errorIcon)
                .font(.system(size: 64))
                .foregroundStyle(errorColor)
            
            Text(errorTitle)
                .font(.headline)
            
            Text(viewModel.errorMessage ?? "An unknown error occurred")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)

            Text(viewModel.statusMessage)
                .font(.caption)
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

    private var errorTitle: String {
        switch viewModel.errorCategory {
        case .rejected:
            return "Request Rejected on Device"
        case .timeout:
            return "Confirmation Timed Out"
        case .disconnected:
            return "Device Disconnected"
        case .mismatch:
            return "Wrong Hardware Account"
        case .wrongApp:
            return "Wrong App or Path"
        case .unavailable:
            return "Signing Not Available"
        case .generic:
            return "Signing Failed"
        }
    }

    private var errorIcon: String {
        switch viewModel.errorCategory {
        case .rejected:
            return "xmark.shield.fill"
        case .timeout:
            return "clock.badge.exclamationmark"
        case .disconnected:
            return "cable.connector.slash"
        case .mismatch:
            return "person.crop.circle.badge.exclamationmark"
        case .wrongApp:
            return "app.badge.checkmark"
        case .unavailable:
            return "nosign"
        case .generic:
            return "exclamationmark.triangle.fill"
        }
    }

    private var errorColor: Color {
        switch viewModel.errorCategory {
        case .timeout:
            return .orange
        case .unavailable:
            return .yellow
        default:
            return .red
        }
    }
}

// MARK: - Preview

#if false // Disabled #Preview for command-line builds
#if false
#if false
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
#endif
#endif
#endif
