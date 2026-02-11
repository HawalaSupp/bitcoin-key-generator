//
//  DeviceSelectionView.swift
//  Hawala
//
//  Reusable view for selecting a hardware wallet device.
//  Used in both setup flows and signing flows when multiple devices are available.
//

import SwiftUI

// MARK: - Device Selection View

/// Displays discovered hardware wallet devices for selection
struct DeviceSelectionView: View {
    @ObservedObject var manager: HardwareWalletManagerV2
    let onSelect: (DiscoveredDevice) -> Void
    let filterDeviceType: HardwareDeviceType?
    
    @State private var isScanning = false
    @State private var animationOffset: CGFloat = 0
    
    init(
        manager: HardwareWalletManagerV2 = .shared,
        filterDeviceType: HardwareDeviceType? = nil,
        onSelect: @escaping (DiscoveredDevice) -> Void
    ) {
        self.manager = manager
        self.filterDeviceType = filterDeviceType
        self.onSelect = onSelect
    }
    
    var filteredDevices: [DiscoveredDevice] {
        if let filter = filterDeviceType {
            return manager.discoveredDevices.filter { $0.deviceType == filter }
        }
        return manager.discoveredDevices
    }
    
    var body: some View {
        VStack(spacing: 20) {
            // Header
            headerSection
            
            // Scanning animation
            if isScanning && filteredDevices.isEmpty {
                scanningIndicator
            }
            
            // Device list
            if !filteredDevices.isEmpty {
                deviceList
            } else if !isScanning {
                noDevicesView
            }
            
            Spacer()
            
            // Refresh button
            refreshButton
        }
        .padding()
        .onAppear {
            startScanning()
        }
        .onDisappear {
            manager.stopScanning()
        }
    }
    
    // MARK: - Subviews
    
    private var headerSection: some View {
        VStack(spacing: 8) {
            Image(systemName: "cable.connector.horizontal")
                .font(.system(size: 48))
                .foregroundColor(.accentColor)
            
            Text("Connect Hardware Wallet")
                .font(.title2)
                .fontWeight(.bold)
            
            Text("Connect your Ledger or Trezor device via USB or Bluetooth")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
    }
    
    private var scanningIndicator: some View {
        VStack(spacing: 16) {
            ZStack {
                Circle()
                    .stroke(Color.accentColor.opacity(0.2), lineWidth: 4)
                    .frame(width: 100, height: 100)
                
                Circle()
                    .trim(from: 0, to: 0.3)
                    .stroke(Color.accentColor, lineWidth: 4)
                    .frame(width: 100, height: 100)
                    .rotationEffect(.degrees(animationOffset))
                
                Image(systemName: "magnifyingglass")
                    .font(.title)
                    .foregroundColor(.accentColor)
            }
            .onAppear {
                withAnimation(Animation.linear(duration: 1).repeatForever(autoreverses: false)) {
                    animationOffset = 360
                }
            }
            
            Text("Searching for devices...")
                .font(.headline)
                .foregroundColor(.secondary)
            
            Text("Make sure your device is unlocked and connected")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding(.vertical, 40)
    }
    
    private var deviceList: some View {
        VStack(spacing: 12) {
            ForEach(filteredDevices) { device in
                DeviceRowView(device: device) {
                    onSelect(device)
                }
            }
        }
    }
    
    private var noDevicesView: some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 40))
                .foregroundColor(.orange)
            
            Text("No devices found")
                .font(.headline)
            
            Text("Ensure your device is connected and unlocked")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(.vertical, 40)
    }
    
    private var refreshButton: some View {
        Button(action: {
            startScanning()
        }) {
            HStack {
                Image(systemName: "arrow.clockwise")
                Text("Refresh")
            }
            .frame(maxWidth: .infinity)
            .padding()
            .background(Color.accentColor.opacity(0.1))
            .cornerRadius(12)
        }
        .disabled(isScanning)
    }
    
    // MARK: - Actions
    
    private func startScanning() {
        isScanning = true
        animationOffset = 0
        manager.startScanning()
        
        // Stop scanning after timeout
        DispatchQueue.main.asyncAfter(deadline: .now() + 10) {
            isScanning = false
        }
    }
}

// MARK: - Device Row View

struct DeviceRowView: View {
    let device: DiscoveredDevice
    let onTap: () -> Void
    
    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 16) {
                // Device icon
                deviceIcon
                
                // Device info
                VStack(alignment: .leading, spacing: 4) {
                    Text(device.name ?? device.deviceType.displayName)
                        .font(.headline)
                        .foregroundColor(.primary)
                    
                    HStack(spacing: 8) {
                        connectionBadge
                    }
                }
                
                Spacer()
                
                Image(systemName: "chevron.right")
                    .foregroundColor(.secondary)
            }
            .padding()
            .background(Color(.systemGray).opacity(0.1))
            .cornerRadius(12)
        }
        .buttonStyle(.plain)
    }
    
    private var deviceIcon: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 10)
                .fill(device.deviceType.brandColor.opacity(0.2))
                .frame(width: 50, height: 50)
            
            Image(systemName: device.deviceType.iconName)
                .font(.title2)
                .foregroundColor(device.deviceType.brandColor)
        }
    }
    
    private var connectionBadge: some View {
        HStack(spacing: 4) {
            Image(systemName: device.connectionType.iconName)
                .font(.caption2)
            Text(device.connectionType.displayName)
                .font(.caption)
        }
        .foregroundColor(.secondary)
    }
}

// MARK: - Hardware Device Type Extension

extension HardwareDeviceType {
    var iconName: String {
        switch self {
        case .ledgerNanoS, .ledgerNanoSPlus:
            return "rectangle.portrait.and.arrow.right"
        case .ledgerNanoX:
            return "rectangle.portrait.and.arrow.right.fill"
        case .ledgerStax:
            return "rectangle.portrait.fill"
        case .trezorOne:
            return "shield"
        case .trezorModelT:
            return "shield.fill"
        case .trezorSafe3:
            return "shield.checkerboard"
        }
    }
    
    var brandColor: Color {
        switch self {
        case .ledgerNanoS, .ledgerNanoSPlus, .ledgerNanoX, .ledgerStax:
            return Color(red: 0.0, green: 0.4, blue: 0.8)  // Ledger blue
        case .trezorOne, .trezorModelT, .trezorSafe3:
            return Color(red: 0.0, green: 0.6, blue: 0.2)  // Trezor green
        }
    }
}

extension DiscoveredDevice.ConnectionType {
    var iconName: String {
        switch self {
        case .usb:
            return "cable.connector"
        case .bluetooth:
            return "dot.radiowaves.left.and.right"
        }
    }
    
    var displayName: String {
        switch self {
        case .usb:
            return "USB"
        case .bluetooth:
            return "Bluetooth"
        }
    }
}

// MARK: - Hardware Wallet Account Badge

/// Badge to display on account cards indicating hardware wallet type
struct HardwareWalletBadge: View {
    let deviceType: HardwareDeviceType
    
    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: deviceType.iconName)
                .font(.caption2)
            Text(deviceType.shortName)
                .font(.caption2)
                .fontWeight(.medium)
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .background(deviceType.brandColor.opacity(0.2))
        .foregroundColor(deviceType.brandColor)
        .cornerRadius(4)
    }
}

extension HardwareDeviceType {
    var shortName: String {
        switch self {
        case .ledgerNanoS:
            return "Nano S"
        case .ledgerNanoSPlus:
            return "Nano S+"
        case .ledgerNanoX:
            return "Nano X"
        case .ledgerStax:
            return "Stax"
        case .trezorOne:
            return "Trezor"
        case .trezorModelT:
            return "Model T"
        case .trezorSafe3:
            return "Safe 3"
        }
    }
}

// MARK: - Preview

#if DEBUG
struct DeviceSelectionView_Previews: PreviewProvider {
    static var previews: some View {
        DeviceSelectionView { device in
            print("Selected: \(device.name ?? "Unknown")")
        }
    }
}
#endif
