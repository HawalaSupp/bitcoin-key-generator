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
        VStack(spacing: 0) {
            // Custom header bar (matches HawalaAssetDetailView)
            HStack {
                Button(action: { dismiss() }) {
                    HStack(spacing: HawalaTheme.Spacing.sm) {
                        Image(systemName: "xmark")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(HawalaTheme.Colors.textSecondary)
                            .frame(width: 28, height: 28)
                            .background(HawalaTheme.Colors.backgroundTertiary)
                            .clipShape(Circle())
                    }
                }
                .buttonStyle(.plain)
                
                Spacer()
                
                // Step indicator
                HStack(spacing: 6) {
                    ForEach(0..<stepCount, id: \.self) { index in
                        Circle()
                            .fill(index <= currentStepIndex
                                  ? HawalaTheme.Colors.accent
                                  : HawalaTheme.Colors.backgroundTertiary)
                            .frame(width: 6, height: 6)
                    }
                }
                
                Spacer()
                
                Text("Hardware Wallet")
                    .font(HawalaTheme.Typography.h4)
                    .foregroundColor(HawalaTheme.Colors.textPrimary)
                    .opacity(0) // Invisible spacer to center the dots
            }
            .padding(.horizontal, HawalaTheme.Spacing.xl)
            .padding(.vertical, HawalaTheme.Spacing.lg)
            .background(HawalaTheme.Colors.backgroundSecondary)
            
            // Content
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
        }
        .frame(minWidth: 500, minHeight: 480)
        .background(HawalaTheme.Colors.background)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .preferredColorScheme(.dark)
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
    
    private var stepCount: Int { 4 }
    
    private var currentStepIndex: Int {
        switch viewModel.step {
        case .discovery: return 0
        case .connecting: return 1
        case .selectApp: return 1
        case .verifyAddress: return 2
        case .complete: return 3
        case .error: return 0
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
        // ROADMAP-22: Track pairing started
        AnalyticsService.shared.track(AnalyticsService.EventName.hwPairingStarted, properties: [
            "device_type": device.deviceType.rawValue
        ])
        
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
            // ROADMAP-22: Track pairing failure
            AnalyticsService.shared.track(AnalyticsService.EventName.hwPairingFailed, properties: [
                "device_type": selectedDevice?.deviceType.rawValue ?? "unknown",
                "error": error.localizedDescription
            ])
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
        
        // ROADMAP-22: Track address verified on device
        AnalyticsService.shared.track(AnalyticsService.EventName.hwAddressVerified, properties: [
            "device_type": device.deviceType.rawValue
        ])
        
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
        VStack(spacing: 0) {
            ScrollView {
                VStack(spacing: HawalaTheme.Spacing.xl) {
                    // Hero icon
                    VStack(spacing: HawalaTheme.Spacing.lg) {
                        ZStack {
                            Circle()
                                .fill(HawalaTheme.Colors.accent.opacity(0.12))
                                .frame(width: 80, height: 80)
                            
                            Image(systemName: "cable.connector.horizontal")
                                .font(.system(size: 32, weight: .medium))
                                .foregroundStyle(HawalaTheme.Colors.accent)
                        }
                        
                        VStack(spacing: HawalaTheme.Spacing.sm) {
                            Text("Connect Your Hardware Wallet")
                                .font(HawalaTheme.Typography.h3)
                                .foregroundColor(HawalaTheme.Colors.textPrimary)
                            
                            Text("Connect your Ledger or Trezor device via USB or Bluetooth")
                                .font(HawalaTheme.Typography.bodySmall)
                                .foregroundColor(HawalaTheme.Colors.textSecondary)
                                .multilineTextAlignment(.center)
                        }
                    }
                    .padding(.top, HawalaTheme.Spacing.xl)
                    
                    // Device list or scanning indicator
                    if viewModel.discoveredDevices.isEmpty {
                        VStack(spacing: HawalaTheme.Spacing.lg) {
                            ProgressView()
                                .scaleEffect(1.2)
                                .tint(HawalaTheme.Colors.accent)
                            
                            Text("Scanning for devices…")
                                .font(HawalaTheme.Typography.bodySmall)
                                .foregroundColor(HawalaTheme.Colors.textTertiary)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 40)
                    } else {
                        VStack(spacing: HawalaTheme.Spacing.md) {
                            ForEach(viewModel.discoveredDevices) { device in
                                DeviceRow(device: device) {
                                    viewModel.selectDevice(device)
                                }
                            }
                        }
                    }
                    
                    // Instructions card
                    VStack(alignment: .leading, spacing: 10) {
                        Label("Unlock your device", systemImage: "lock.open")
                        Label("Connect via USB or enable Bluetooth", systemImage: "cable.connector")
                        Label("Ensure the required app is installed", systemImage: "app.badge.checkmark")
                    }
                    .font(HawalaTheme.Typography.caption)
                    .foregroundColor(HawalaTheme.Colors.textSecondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .hawalaCard(padding: HawalaTheme.Spacing.lg)
                }
                .padding(.horizontal, HawalaTheme.Spacing.xl)
                .padding(.bottom, HawalaTheme.Spacing.xl)
            }
        }
    }
}

struct DeviceRow: View {
    let device: DiscoveredDevice
    let onSelect: () -> Void
    
    @State private var isHovered = false
    
    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: HawalaTheme.Spacing.lg) {
                // Device icon
                ZStack {
                    Circle()
                        .fill(HawalaTheme.Colors.accent.opacity(0.12))
                        .frame(width: 44, height: 44)
                    
                    Image(systemName: deviceIcon)
                        .font(.system(size: 18, weight: .medium))
                        .foregroundColor(HawalaTheme.Colors.accent)
                }
                
                VStack(alignment: .leading, spacing: 3) {
                    Text(device.name ?? device.deviceType.displayName)
                        .font(HawalaTheme.Typography.h4)
                        .foregroundColor(HawalaTheme.Colors.textPrimary)
                    
                    HStack(spacing: 6) {
                        Image(systemName: device.connectionType == .usb ? "cable.connector" : "wave.3.right")
                            .font(.system(size: 10))
                        Text(device.connectionType == .usb ? "USB" : "Bluetooth")
                            .font(HawalaTheme.Typography.caption)
                    }
                    .foregroundColor(HawalaTheme.Colors.textTertiary)
                }
                
                Spacer()
                
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(HawalaTheme.Colors.textTertiary)
            }
            .padding(HawalaTheme.Spacing.lg)
            .background(
                RoundedRectangle(cornerRadius: HawalaTheme.Radius.lg, style: .continuous)
                    .fill(HawalaTheme.Colors.backgroundSecondary)
            )
            .overlay(
                RoundedRectangle(cornerRadius: HawalaTheme.Radius.lg, style: .continuous)
                    .strokeBorder(
                        isHovered ? HawalaTheme.Colors.accent.opacity(0.3) : HawalaTheme.Colors.border,
                        lineWidth: 1
                    )
            )
            .scaleEffect(isHovered ? 1.01 : 1.0)
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            withAnimation(.easeOut(duration: 0.15)) {
                isHovered = hovering
            }
        }
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
        VStack(spacing: HawalaTheme.Spacing.xl) {
            Spacer()
            
            ZStack {
                Circle()
                    .fill(HawalaTheme.Colors.accent.opacity(0.08))
                    .frame(width: 100, height: 100)
                
                ProgressView()
                    .scaleEffect(1.5)
                    .tint(HawalaTheme.Colors.accent)
            }
            
            VStack(spacing: HawalaTheme.Spacing.sm) {
                Text(viewModel.statusMessage)
                    .font(HawalaTheme.Typography.h3)
                    .foregroundColor(HawalaTheme.Colors.textPrimary)
                
                if let device = viewModel.selectedDevice {
                    Text(device.deviceType.displayName)
                        .font(HawalaTheme.Typography.bodySmall)
                        .foregroundColor(HawalaTheme.Colors.textSecondary)
                }
            }
            
            Spacer()
        }
        .frame(maxWidth: .infinity)
        .padding(HawalaTheme.Spacing.xl)
    }
}

// MARK: - Select App View

struct SelectAppView: View {
    @ObservedObject var viewModel: HardwareWalletSetupViewModel
    let chain: SupportedChain
    
    var body: some View {
        VStack(spacing: HawalaTheme.Spacing.xl) {
            Spacer()
            
            ZStack {
                Circle()
                    .fill(Color.orange.opacity(0.12))
                    .frame(width: 88, height: 88)
                
                Image(systemName: "app.badge")
                    .font(.system(size: 36, weight: .medium))
                    .foregroundColor(.orange)
            }
            
            VStack(spacing: HawalaTheme.Spacing.md) {
                Text("Open the \(chain.ledgerAppName) App")
                    .font(HawalaTheme.Typography.h3)
                    .foregroundColor(HawalaTheme.Colors.textPrimary)
                
                Text("Please open the \(chain.ledgerAppName) app on your hardware wallet to continue.")
                    .font(HawalaTheme.Typography.bodySmall)
                    .foregroundColor(HawalaTheme.Colors.textSecondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, HawalaTheme.Spacing.xl)
            }
            
            Spacer()
            
            Button {
                viewModel.proceedToVerify()
            } label: {
                Text("Continue")
                    .font(HawalaTheme.Typography.body.weight(.semibold))
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(HawalaTheme.Colors.accent)
                    .clipShape(RoundedRectangle(cornerRadius: HawalaTheme.Radius.md, style: .continuous))
            }
            .buttonStyle(.plain)
            .disabled(viewModel.isLoading)
            .opacity(viewModel.isLoading ? 0.5 : 1)
            .padding(.horizontal, HawalaTheme.Spacing.xl)
            .padding(.bottom, HawalaTheme.Spacing.xl)
        }
    }
}

// MARK: - Verify Address View

struct VerifyAddressView: View {
    @ObservedObject var viewModel: HardwareWalletSetupViewModel
    
    var body: some View {
        VStack(spacing: HawalaTheme.Spacing.xl) {
            if viewModel.isLoading {
                Spacer()
                ZStack {
                    Circle()
                        .fill(HawalaTheme.Colors.accent.opacity(0.08))
                        .frame(width: 80, height: 80)
                    
                    ProgressView()
                        .scaleEffect(1.2)
                        .tint(HawalaTheme.Colors.accent)
                }
                Text(viewModel.statusMessage)
                    .font(HawalaTheme.Typography.bodySmall)
                    .foregroundColor(HawalaTheme.Colors.textSecondary)
                Spacer()
            } else if let address = viewModel.derivedAddress {
                ScrollView {
                    VStack(spacing: HawalaTheme.Spacing.xl) {
                        // Icon
                        ZStack {
                            Circle()
                                .fill(HawalaTheme.Colors.success.opacity(0.12))
                                .frame(width: 72, height: 72)
                            
                            Image(systemName: "checkmark.shield")
                                .font(.system(size: 28, weight: .medium))
                                .foregroundColor(HawalaTheme.Colors.success)
                        }
                        .padding(.top, HawalaTheme.Spacing.lg)
                        
                        VStack(spacing: HawalaTheme.Spacing.sm) {
                            Text("Verify Address")
                                .font(HawalaTheme.Typography.h3)
                                .foregroundColor(HawalaTheme.Colors.textPrimary)
                            
                            Text("Verify this address matches your device display")
                                .font(HawalaTheme.Typography.bodySmall)
                                .foregroundColor(HawalaTheme.Colors.textSecondary)
                                .multilineTextAlignment(.center)
                        }
                        
                        // Address card
                        VStack(spacing: HawalaTheme.Spacing.md) {
                            Text(address.address)
                                .font(.system(size: 14, weight: .medium, design: .monospaced))
                                .foregroundColor(HawalaTheme.Colors.textPrimary)
                                .multilineTextAlignment(.center)
                            
                            Text("Path: \(address.path.description)")
                                .font(HawalaTheme.Typography.caption)
                                .foregroundColor(HawalaTheme.Colors.textTertiary)
                        }
                        .hawalaCard(padding: HawalaTheme.Spacing.lg)
                        
                        // Buttons
                        VStack(spacing: HawalaTheme.Spacing.md) {
                            Button {
                                viewModel.confirmAddress()
                            } label: {
                                HStack(spacing: 8) {
                                    Image(systemName: "checkmark.circle.fill")
                                        .font(.system(size: 16))
                                    Text("Address Matches")
                                        .font(HawalaTheme.Typography.body.weight(.semibold))
                                }
                                .foregroundColor(.white)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 12)
                                .background(HawalaTheme.Colors.success)
                                .clipShape(RoundedRectangle(cornerRadius: HawalaTheme.Radius.md, style: .continuous))
                            }
                            .buttonStyle(.plain)
                            
                            Button {
                                viewModel.errorMessage = "Address mismatch. Please try again."
                                viewModel.step = .error
                            } label: {
                                HStack(spacing: 8) {
                                    Image(systemName: "xmark.circle.fill")
                                        .font(.system(size: 16))
                                    Text("Address Doesn't Match")
                                        .font(HawalaTheme.Typography.body.weight(.semibold))
                                }
                                .foregroundColor(HawalaTheme.Colors.error)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 12)
                                .background(HawalaTheme.Colors.error.opacity(0.12))
                                .clipShape(RoundedRectangle(cornerRadius: HawalaTheme.Radius.md, style: .continuous))
                                .overlay(
                                    RoundedRectangle(cornerRadius: HawalaTheme.Radius.md, style: .continuous)
                                        .strokeBorder(HawalaTheme.Colors.error.opacity(0.3), lineWidth: 1)
                                )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, HawalaTheme.Spacing.xl)
                    .padding(.bottom, HawalaTheme.Spacing.xl)
                }
            }
        }
    }
}

// MARK: - Complete View

struct CompleteView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var viewModel: HardwareWalletSetupViewModel
    
    var body: some View {
        VStack(spacing: HawalaTheme.Spacing.xl) {
            Spacer()
            
            ZStack {
                Circle()
                    .fill(HawalaTheme.Colors.success.opacity(0.12))
                    .frame(width: 96, height: 96)
                
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 48, weight: .medium))
                    .foregroundColor(HawalaTheme.Colors.success)
            }
            
            VStack(spacing: HawalaTheme.Spacing.md) {
                Text("Hardware Wallet Added")
                    .font(HawalaTheme.Typography.h2)
                    .foregroundColor(HawalaTheme.Colors.textPrimary)
                
                if let account = viewModel.createdAccount {
                    VStack(spacing: HawalaTheme.Spacing.sm) {
                        Text(account.deviceType.displayName)
                            .font(HawalaTheme.Typography.h4)
                            .foregroundColor(HawalaTheme.Colors.textSecondary)
                        
                        Text(truncateAddress(account.address))
                            .font(.system(size: 13, weight: .medium, design: .monospaced))
                            .foregroundColor(HawalaTheme.Colors.textTertiary)
                    }
                    .hawalaCard(padding: HawalaTheme.Spacing.lg)
                }
            }
            
            Spacer()
            
            Button {
                dismiss()
            } label: {
                Text("Done")
                    .font(HawalaTheme.Typography.body.weight(.semibold))
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(HawalaTheme.Colors.accent)
                    .clipShape(RoundedRectangle(cornerRadius: HawalaTheme.Radius.md, style: .continuous))
            }
            .buttonStyle(.plain)
            .padding(.horizontal, HawalaTheme.Spacing.xl)
            .padding(.bottom, HawalaTheme.Spacing.xl)
        }
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
        VStack(spacing: HawalaTheme.Spacing.xl) {
            Spacer()
            
            ZStack {
                Circle()
                    .fill(HawalaTheme.Colors.error.opacity(0.12))
                    .frame(width: 88, height: 88)
                
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 36, weight: .medium))
                    .foregroundColor(HawalaTheme.Colors.error)
            }
            
            VStack(spacing: HawalaTheme.Spacing.md) {
                Text("Connection Error")
                    .font(HawalaTheme.Typography.h3)
                    .foregroundColor(HawalaTheme.Colors.textPrimary)
                
                Text(viewModel.errorMessage ?? "An unknown error occurred")
                    .font(HawalaTheme.Typography.bodySmall)
                    .foregroundColor(HawalaTheme.Colors.textSecondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, HawalaTheme.Spacing.xl)
            }
            
            Spacer()
            
            VStack(spacing: HawalaTheme.Spacing.md) {
                Button {
                    viewModel.retryConnection()
                } label: {
                    Text("Try Again")
                        .font(HawalaTheme.Typography.body.weight(.semibold))
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(HawalaTheme.Colors.accent)
                        .clipShape(RoundedRectangle(cornerRadius: HawalaTheme.Radius.md, style: .continuous))
                }
                .buttonStyle(.plain)
                
                Button {
                    viewModel.startOver()
                } label: {
                    Text("Start Over")
                        .font(HawalaTheme.Typography.body.weight(.medium))
                        .foregroundColor(HawalaTheme.Colors.textSecondary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(HawalaTheme.Colors.backgroundTertiary)
                        .clipShape(RoundedRectangle(cornerRadius: HawalaTheme.Radius.md, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: HawalaTheme.Radius.md, style: .continuous)
                                .strokeBorder(HawalaTheme.Colors.border, lineWidth: 1)
                        )
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, HawalaTheme.Spacing.xl)
            .padding(.bottom, HawalaTheme.Spacing.xl)
        }
    }
}

// MARK: - Preview

#if false // Disabled #Preview for command-line builds
#if false
#if false
#Preview {
    HardwareWalletSetupSheet(chain: .ethereum) { account in
        print("Created account: \(account.address)")
    }
}
#endif
#endif
#endif
