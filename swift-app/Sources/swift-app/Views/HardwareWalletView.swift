import SwiftUI

/// Hardware wallet management view
struct HardwareWalletView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var hwManager = HardwareWalletManager.shared
    @State private var showAddAddress = false
    @State private var selectedDevice: ConnectedHardwareWallet?
    @State private var errorMessage: String?
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            headerView
            
            Divider()
            
            ScrollView {
                VStack(spacing: 20) {
                    // Connected devices
                    devicesSection
                    
                    // Saved addresses
                    if !hwManager.savedAddresses.isEmpty {
                        addressesSection
                    }
                    
                    // Instructions
                    instructionsSection
                }
                .padding()
            }
        }
        .frame(minWidth: 550, idealWidth: 600, minHeight: 450, idealHeight: 500)
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
            
            Text("Hardware Wallets")
                .font(.headline)
            
            Spacer()
            
            Button {
                hwManager.refreshDevices()
            } label: {
                Image(systemName: "arrow.clockwise")
            }
            .buttonStyle(.plain)
        }
        .padding()
    }
    
    private var devicesSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Connected Devices")
                    .font(.headline)
                
                Spacer()
                
                if hwManager.isScanning {
                    HStack(spacing: 6) {
                        ProgressView()
                            .scaleEffect(0.7)
                        Text("Scanning...")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            
            if hwManager.connectedDevices.isEmpty {
                HStack {
                    Image(systemName: "cable.connector.horizontal")
                        .font(.title)
                        .foregroundStyle(.secondary)
                    
                    VStack(alignment: .leading, spacing: 4) {
                        Text("No devices connected")
                            .font(.subheadline)
                        Text("Connect your Ledger or Trezor via USB")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding()
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.primary.opacity(0.05))
                .cornerRadius(10)
            } else {
                ForEach(hwManager.connectedDevices) { device in
                    DeviceCard(device: device) {
                        selectedDevice = device
                        // Would trigger address derivation
                    }
                }
            }
        }
    }
    
    private var addressesSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Saved Addresses")
                .font(.headline)
            
            ForEach(hwManager.savedAddresses) { address in
                HWAddressCard(address: address) {
                    hwManager.deleteAddress(address)
                }
            }
        }
    }
    
    private var instructionsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("How to Use")
                .font(.headline)
            
            VStack(alignment: .leading, spacing: 8) {
                InstructionRow(number: 1, text: "Connect your hardware wallet via USB")
                InstructionRow(number: 2, text: "Unlock the device with your PIN")
                InstructionRow(number: 3, text: "Open the appropriate app (Bitcoin, Ethereum, etc.)")
                InstructionRow(number: 4, text: "Click 'Get Address' to derive and verify addresses")
                InstructionRow(number: 5, text: "Sign transactions by approving on the device screen")
            }
            .padding()
            .background(Color.blue.opacity(0.05))
            .cornerRadius(10)
            
            // Supported devices
            VStack(alignment: .leading, spacing: 8) {
                Text("Supported Devices")
                    .font(.subheadline)
                    .fontWeight(.medium)
                
                HStack(spacing: 16) {
                    ForEach(HardwareWalletType.allCases, id: \.self) { type in
                        Text(type.displayName)
                            .font(.caption)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 4)
                            .background(Color.secondary.opacity(0.1))
                            .cornerRadius(6)
                    }
                }
            }
            .padding()
            .background(Color.primary.opacity(0.03))
            .cornerRadius(10)
        }
    }
}

// MARK: - Supporting Views

struct DeviceCard: View {
    let device: ConnectedHardwareWallet
    let onGetAddress: () -> Void
    
    var body: some View {
        HStack {
            // Device icon
            Image(systemName: device.type.isLedger ? "creditcard" : "lock.shield")
                .font(.title2)
                .foregroundStyle(.blue)
                .frame(width: 40)
            
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(device.type.displayName)
                        .font(.headline)
                    
                    Circle()
                        .fill(device.isConnected ? .green : .red)
                        .frame(width: 8, height: 8)
                }
                
                if let app = device.appOpen {
                    Text("\(app) app open")
                        .font(.caption)
                        .foregroundStyle(.green)
                } else {
                    Text("Please open an app on device")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
                
                if let version = device.firmwareVersion {
                    Text("Firmware: \(version)")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }
            
            Spacer()
            
            Button("Get Address") {
                onGetAddress()
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
        }
        .padding()
        .background(Color.primary.opacity(0.05))
        .cornerRadius(10)
    }
}

struct HWAddressCard: View {
    let address: HardwareWalletAddress
    let onDelete: () -> Void
    
    @State private var showDeleteConfirm = false
    
    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(address.label ?? address.chain.capitalized)
                        .font(.headline)
                    
                    Text(address.walletType.displayName)
                        .font(.caption2)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.blue.opacity(0.15))
                        .foregroundStyle(.blue)
                        .clipShape(Capsule())
                }
                
                Text(address.address)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                
                Text(address.derivationPath)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            
            Spacer()
            
            HStack(spacing: 8) {
                Button {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(address.address, forType: .string)
                } label: {
                    Image(systemName: "doc.on.doc")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                
                Button(role: .destructive) {
                    showDeleteConfirm = true
                } label: {
                    Image(systemName: "trash")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
        }
        .padding()
        .background(Color.primary.opacity(0.03))
        .cornerRadius(10)
        .confirmationDialog("Delete Address?", isPresented: $showDeleteConfirm) {
            Button("Delete", role: .destructive) { onDelete() }
            Button("Cancel", role: .cancel) { }
        }
    }
}

struct InstructionRow: View {
    let number: Int
    let text: String
    
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Text("\(number)")
                .font(.caption)
                .fontWeight(.bold)
                .foregroundStyle(.white)
                .frame(width: 20, height: 20)
                .background(Color.blue)
                .clipShape(Circle())
            
            Text(text)
                .font(.subheadline)
        }
    }
}

#Preview {
    HardwareWalletView()
}
