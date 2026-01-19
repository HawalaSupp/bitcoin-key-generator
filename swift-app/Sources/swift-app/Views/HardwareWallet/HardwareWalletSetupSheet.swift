//
//  HardwareWalletSetupSheet.swift
//  Hawala
//
//  Hardware Wallet Setup Flow
//
//  Guides users through connecting and setting up their hardware wallet,
//  including device discovery, app selection, and address verification.
//

import SwiftUI

// MARK: - Setup Sheet

/// Main sheet for hardware wallet setup
struct HardwareWalletSetupSheet: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var viewModel = HardwareWalletSetupViewModel()
    
    let chain: SupportedChain
    let onComplete: (HardwareWalletAccount) -> Void
    
    var body: some View {
        NavigationStack {
            Group {
                switch viewModel.step {
                case .discovery:
                    DeviceDiscoveryView(viewModel: viewModel)
                case .connecting:
                    ConnectingView(viewModel: viewModel)
                case .selectApp:
                    SelectAppView(viewModel: viewModel, chain: chain)
                case .verifyAddress:
                    VerifyAddressView(viewModel: viewModel)
                case .complete:
                    CompleteView(viewModel: viewModel)
                case .error:
                    ErrorView(viewModel: viewModel)
                }
            }
            .navigationTitle("Hardware Wallet")
            .toolbar(id: "setupToolbar") {
                ToolbarItem(id: "cancel", placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
            }
        }
        .onAppear {
            viewModel.selectedChain = chain
            viewModel.startDiscovery()
        }
        .onDisappear {
            viewModel.stopDiscovery()
        }
        .onReceive(viewModel.$step) { newStep in
            if newStep == .complete, let account = viewModel.createdAccount {
                onComplete(account)
            }
        }
    }
}

// MARK: - View Model

@MainActor
class HardwareWalletSetupViewModel: ObservableObject {
    enum SetupStep {
        case discovery
        case connecting
        case selectApp
        case verifyAddress
        case complete
        case error
    }
    
    @Published var step: SetupStep = .discovery
    @Published var discoveredDevices: [DiscoveredDevice] = []
    @Published var selectedDevice: DiscoveredDevice?
    @Published var connectedWallet: HardwareWallet?
    @Published var derivedAddress: AddressResult?
    @Published var createdAccount: HardwareWalletAccount?
    @Published var errorMessage: String?
    @Published var isLoading = false
    @Published var statusMessage = "Looking for devices..."
    
    var selectedChain: SupportedChain = .ethereum
    var selectedPath: DerivationPath?
    
    private let manager = HardwareWalletManagerV2.shared
    
    func startDiscovery() {
        manager.onDeviceDiscovered = { [weak self] device in
            Task { @MainActor in
                if !(self?.discoveredDevices.contains(where: { $0.id == device.id }) ?? true) {
                    self?.discoveredDevices.append(device)
                }
            }
        }
        
        manager.onDeviceRemoved = { [weak self] device in
            Task { @MainActor in
                self?.discoveredDevices.removeAll { $0.id == device.id }
            }
        }
        
        manager.startScanning()
    }
    
    func stopDiscovery() {
        manager.stopScanning()
    }
    
    func selectDevice(_ device: DiscoveredDevice) {
        selectedDevice = device
        step = .connecting
        
        Task {
            await connectToDevice(device)
        }
    }
    
    func connectToDevice(_ device: DiscoveredDevice) async {
        isLoading = true
        statusMessage = "Connecting to \(device.deviceType.displayName)..."
        
        do {
            let wallet = try await manager.connect(to: device)
            connectedWallet = wallet
            
            // Check if we need to prompt for app
            let status = await wallet.connectionStatus
            switch status {
            case .requiresAppOpen(let appName):
                statusMessage = "Please open the \(appName) app on your device"
                step = .selectApp
            case .ready:
                step = .verifyAddress
                await deriveAddress()
            default:
                step = .selectApp
            }
        } catch {
            errorMessage = error.localizedDescription
            step = .error
        }
        
        isLoading = false
    }
    
    func retryConnection() {
        guard let device = selectedDevice else { return }
        step = .connecting
        Task {
            await connectToDevice(device)
        }
    }
    
    func proceedToVerify() {
        step = .verifyAddress
        Task {
            await deriveAddress()
        }
    }
    
    func deriveAddress() async {
        isLoading = true
        statusMessage = "Deriving address..."
        
        guard let device = selectedDevice else {
            errorMessage = "No device selected"
            step = .error
            isLoading = false
            return
        }
        
        do {
            let path = selectedPath ?? DerivationPath(string: selectedChain.defaultPath)!
            
            let address = try await manager.getAddress(
                deviceId: device.id,
                path: path,
                chain: selectedChain,
                verify: true
            )
            
            derivedAddress = address
            statusMessage = "Verify the address on your device"
            
        } catch {
            errorMessage = error.localizedDescription
            step = .error
        }
        
        isLoading = false
    }
    
    func confirmAddress() {
        guard let device = selectedDevice,
              let address = derivedAddress else { return }
        
        let path = selectedPath ?? DerivationPath(string: selectedChain.defaultPath)!
        
        let account = HardwareWalletAccount(
            deviceType: device.deviceType,
            chain: selectedChain,
            derivationPath: path.description,
            address: address.address,
            publicKey: address.publicKey?.map { String(format: "%02x", $0) }.joined() ?? ""
        )
        
        manager.addAccount(account)
        createdAccount = account
        step = .complete
    }
    
    func startOver() {
        selectedDevice = nil
        connectedWallet = nil
        derivedAddress = nil
        createdAccount = nil
        errorMessage = nil
        step = .discovery
    }
}

// MARK: - Discovery View

struct DeviceDiscoveryView: View {
    @ObservedObject var viewModel: HardwareWalletSetupViewModel
    
    var body: some View {
        VStack(spacing: 24) {
            // Header
            VStack(spacing: 12) {
                Image(systemName: "cable.connector.horizontal")
                    .font(.system(size: 48))
                    .foregroundStyle(.blue)
                
                Text("Connect Your Hardware Wallet")
                    .font(.headline)
                
                Text("Connect your Ledger or Trezor device via USB or Bluetooth")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .padding(.top, 32)
            
            Divider()
            
            // Device list
            if viewModel.discoveredDevices.isEmpty {
                VStack(spacing: 16) {
                    ProgressView()
                        .scaleEffect(1.2)
                    
                    Text("Looking for devices...")
                        .foregroundStyle(.secondary)
                }
                .frame(maxHeight: .infinity)
            } else {
                ScrollView {
                    VStack(spacing: 12) {
                        ForEach(viewModel.discoveredDevices) { device in
                            DeviceRow(device: device) {
                                viewModel.selectDevice(device)
                            }
                        }
                    }
                    .padding(.horizontal)
                }
            }
            
            Spacer()
            
            // Instructions
            VStack(alignment: .leading, spacing: 8) {
                Label("Unlock your device", systemImage: "lock.open")
                Label("Connect via USB or enable Bluetooth", systemImage: "cable.connector")
                Label("Ensure the required app is installed", systemImage: "app.badge.checkmark")
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding()
            .background(.ultraThinMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .padding(.horizontal)
        }
        .padding(.bottom)
    }
}

struct DeviceRow: View {
    let device: DiscoveredDevice
    let onSelect: () -> Void
    
    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: 16) {
                // Device icon
                Image(systemName: deviceIcon)
                    .font(.title2)
                    .foregroundStyle(.blue)
                    .frame(width: 44, height: 44)
                    .background(.blue.opacity(0.1))
                    .clipShape(Circle())
                
                VStack(alignment: .leading, spacing: 4) {
                    Text(device.name ?? device.deviceType.displayName)
                        .font(.headline)
                    
                    Text(device.connectionType == .usb ? "USB" : "Bluetooth")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                
                Spacer()
                
                Image(systemName: "chevron.right")
                    .foregroundStyle(.secondary)
            }
            .padding()
            .background(.ultraThinMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
    }
    
    private var deviceIcon: String {
        switch device.deviceType.manufacturer {
        case .ledger:
            return "creditcard"
        case .trezor:
            return "shield"
        }
    }
}

// MARK: - Connecting View

struct ConnectingView: View {
    @ObservedObject var viewModel: HardwareWalletSetupViewModel
    
    var body: some View {
        VStack(spacing: 24) {
            Spacer()
            
            ProgressView()
                .scaleEffect(1.5)
            
            Text(viewModel.statusMessage)
                .font(.headline)
            
            if let device = viewModel.selectedDevice {
                Text(device.deviceType.displayName)
                    .foregroundStyle(.secondary)
            }
            
            Spacer()
        }
    }
}

// MARK: - Select App View

struct SelectAppView: View {
    @ObservedObject var viewModel: HardwareWalletSetupViewModel
    let chain: SupportedChain
    
    var body: some View {
        VStack(spacing: 24) {
            Spacer()
            
            Image(systemName: "app.badge")
                .font(.system(size: 64))
                .foregroundStyle(.orange)
            
            Text("Open the \(chain.ledgerAppName) App")
                .font(.headline)
            
            Text("Please open the \(chain.ledgerAppName) app on your hardware wallet to continue.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
            
            Spacer()
            
            Button("Continue") {
                viewModel.proceedToVerify()
            }
            .buttonStyle(.borderedProminent)
            .disabled(viewModel.isLoading)
        }
        .padding()
    }
}

// MARK: - Verify Address View

struct VerifyAddressView: View {
    @ObservedObject var viewModel: HardwareWalletSetupViewModel
    
    var body: some View {
        VStack(spacing: 24) {
            if viewModel.isLoading {
                Spacer()
                ProgressView()
                    .scaleEffect(1.2)
                Text(viewModel.statusMessage)
                    .foregroundStyle(.secondary)
                Spacer()
            } else if let address = viewModel.derivedAddress {
                // Address display
                VStack(spacing: 16) {
                    Image(systemName: "checkmark.shield")
                        .font(.system(size: 48))
                        .foregroundStyle(.green)
                    
                    Text("Verify Address")
                        .font(.headline)
                    
                    Text("Please verify this address matches the one shown on your device")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                .padding(.top, 32)
                
                // Address box
                VStack(spacing: 8) {
                    Text(address.address)
                        .font(.system(.body, design: .monospaced))
                        .multilineTextAlignment(.center)
                        .padding()
                        .frame(maxWidth: .infinity)
                        .background(.ultraThinMaterial)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                    
                    Text("Path: \(address.path.description)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal)
                
                Spacer()
                
                // Confirm button
                VStack(spacing: 12) {
                    Button("Address Matches") {
                        viewModel.confirmAddress()
                    }
                    .buttonStyle(.borderedProminent)
                    
                    Button("Address Doesn't Match") {
                        viewModel.errorMessage = "Address mismatch. Please try again."
                        viewModel.step = .error
                    }
                    .buttonStyle(.bordered)
                    .tint(.red)
                }
            }
        }
        .padding()
    }
}

// MARK: - Complete View

struct CompleteView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var viewModel: HardwareWalletSetupViewModel
    
    var body: some View {
        VStack(spacing: 24) {
            Spacer()
            
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 72))
                .foregroundStyle(.green)
            
            Text("Hardware Wallet Added")
                .font(.title2)
                .fontWeight(.bold)
            
            if let account = viewModel.createdAccount {
                VStack(spacing: 8) {
                    Text(account.deviceType.displayName)
                        .font(.headline)
                    
                    Text(truncateAddress(account.address))
                        .font(.system(.body, design: .monospaced))
                        .foregroundStyle(.secondary)
                }
            }
            
            Spacer()
            
            Button("Done") {
                dismiss()
            }
            .buttonStyle(.borderedProminent)
        }
        .padding()
    }
    
    private func truncateAddress(_ address: String) -> String {
        guard address.count > 16 else { return address }
        return "\(address.prefix(8))...\(address.suffix(6))"
    }
}

// MARK: - Error View

struct ErrorView: View {
    @ObservedObject var viewModel: HardwareWalletSetupViewModel
    
    var body: some View {
        VStack(spacing: 24) {
            Spacer()
            
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 64))
                .foregroundStyle(.red)
            
            Text("Connection Error")
                .font(.headline)
            
            Text(viewModel.errorMessage ?? "An unknown error occurred")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
            
            Spacer()
            
            VStack(spacing: 12) {
                Button("Try Again") {
                    viewModel.retryConnection()
                }
                .buttonStyle(.borderedProminent)
                
                Button("Start Over") {
                    viewModel.startOver()
                }
                .buttonStyle(.bordered)
            }
        }
        .padding()
    }
}

// MARK: - Preview

#Preview {
    HardwareWalletSetupSheet(chain: .ethereum) { account in
        print("Created account: \(account.address)")
    }
}
