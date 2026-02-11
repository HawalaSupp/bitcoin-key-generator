//
//  HardwareWalletConnectionBadge.swift
//  Hawala
//
//  ROADMAP-22 E12: Sidebar connection status indicator
//  Displays real-time hardware wallet connection status in the sidebar.
//

import SwiftUI

// MARK: - Sidebar Connection Badge

/// Compact hardware wallet connection indicator for the sidebar
struct HardwareWalletConnectionBadge: View {
    @ObservedObject var manager: HardwareWalletManagerV2
    let onTap: () -> Void

    private var connectedDevice: DiscoveredDevice? {
        manager.discoveredDevices.first
    }

    private var isConnected: Bool {
        !manager.discoveredDevices.isEmpty
    }

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 8) {
                // Connection dot
                Circle()
                    .fill(isConnected ? Color.green : Color.red.opacity(0.6))
                    .frame(width: 8, height: 8)

                if let device = connectedDevice {
                    Image(systemName: device.deviceType.iconName)
                        .font(.caption)
                        .foregroundColor(device.deviceType.brandColor)

                    Text(device.deviceType.shortName)
                        .font(.caption)
                        .fontWeight(.medium)
                        .foregroundColor(.primary)

                    Text(device.connectionType == .usb ? "USB" : "BLE")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                } else {
                    Image(systemName: "cable.connector.horizontal")
                        .font(.caption)
                        .foregroundColor(.secondary)

                    Text("No Device")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                Spacer()

                // Chevron to open full HW view
                Image(systemName: "chevron.right")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(isConnected
                        ? Color.green.opacity(0.08)
                        : Color.primary.opacity(0.04))
            )
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 12)
        .accessibilityLabel(
            isConnected
                ? "Hardware wallet connected: \(connectedDevice?.deviceType.shortName ?? "")"
                : "No hardware wallet connected"
        )
        .accessibilityHint("Opens hardware wallet manager")
    }
}

// MARK: - Firmware Update Banner

/// Optional banner shown when firmware is outdated
struct HardwareWalletFirmwareBanner: View {
    let deviceName: String
    let onUpdate: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundColor(.orange)
                .font(.caption)

            VStack(alignment: .leading, spacing: 2) {
                Text("Firmware Update Available")
                    .font(.caption)
                    .fontWeight(.medium)
                Text("Update your \(deviceName) for the latest security fixes")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }

            Spacer()

            Button("Update", action: onUpdate)
                .font(.caption)
                .buttonStyle(.bordered)
                .controlSize(.mini)
        }
        .padding(10)
        .background(Color.orange.opacity(0.1))
        .cornerRadius(8)
        .padding(.horizontal, 12)
    }
}

// MARK: - Multi-Device Indicator

/// Badge showing number of connected devices when more than one
struct HardwareWalletMultiDeviceBadge: View {
    let count: Int

    var body: some View {
        if count > 1 {
            Text("\(count) devices")
                .font(.caption2)
                .foregroundColor(.white)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(Color.blue)
                .clipShape(Capsule())
        }
    }
}

// MARK: - Preview

#if DEBUG
struct HardwareWalletConnectionBadge_Previews: PreviewProvider {
    static var previews: some View {
        VStack(spacing: 12) {
            HardwareWalletConnectionBadge(
                manager: .shared,
                onTap: {}
            )

            HardwareWalletFirmwareBanner(
                deviceName: "Ledger Nano X",
                onUpdate: {}
            )
        }
        .padding()
        .frame(width: 220)
        .background(Color(.windowBackgroundColor))
    }
}
#endif
