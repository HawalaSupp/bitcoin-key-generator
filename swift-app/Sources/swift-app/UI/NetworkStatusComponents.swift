import SwiftUI
import Combine

// MARK: - Network Status Bar
/// A compact status bar showing WebSocket connection and sync status
struct NetworkStatusBar: View {
    @StateObject private var webSocket = WebSocketPriceService.shared
    @StateObject private var syncService = BackendSyncService.shared
    
    @State private var isExpanded: Bool = false
    
    var body: some View {
        HStack(spacing: HawalaTheme.Spacing.md) {
            // WebSocket status
            WebSocketStatusPill(
                state: webSocket.connectionState,
                lastUpdate: webSocket.lastUpdateTime
            )
            
            // Sync status
            SyncStatusPill(
                isOnline: syncService.isOnline,
                lastSync: syncService.lastFullSyncTime,
                pendingCount: syncService.pendingOperationsCount
            )
        }
        .padding(.horizontal, HawalaTheme.Spacing.md)
        .padding(.vertical, HawalaTheme.Spacing.xs)
        .background(
            Capsule()
                .fill(HawalaTheme.Colors.backgroundSecondary.opacity(0.8))
                .overlay(
                    Capsule()
                        .strokeBorder(Color.white.opacity(0.1), lineWidth: 0.5)
                )
        )
    }
}

// MARK: - WebSocket Status Pill
struct WebSocketStatusPill: View {
    let state: WebSocketState
    let lastUpdate: Date?
    
    var body: some View {
        HStack(spacing: 6) {
            // Status indicator dot - static, no animation
            Circle()
                .fill(statusColor)
                .frame(width: 8, height: 8)
            
            // Status text
            Text(state.isConnected ? "Live" : state.statusText)
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(state.isConnected ? HawalaTheme.Colors.success : HawalaTheme.Colors.textTertiary)
            
            // Timestamp
            if state.isConnected, let lastUpdate = lastUpdate {
                Text("•")
                    .font(.system(size: 8))
                    .foregroundColor(HawalaTheme.Colors.textTertiary)
                
                Text(timeAgo(lastUpdate))
                    .font(.system(size: 10))
                    .foregroundColor(HawalaTheme.Colors.textTertiary)
            }
        }
        .padding(.horizontal, HawalaTheme.Spacing.sm)
        .padding(.vertical, 4)
    }
    
    private var statusColor: Color {
        switch state {
        case .connected: return HawalaTheme.Colors.success
        case .connecting, .reconnecting: return HawalaTheme.Colors.warning
        case .disconnected: return HawalaTheme.Colors.textTertiary
        case .failed: return HawalaTheme.Colors.error
        }
    }
    
    private func timeAgo(_ date: Date) -> String {
        let seconds = Int(Date().timeIntervalSince(date))
        if seconds < 5 { return "now" }
        if seconds < 60 { return "\(seconds)s ago" }
        return "\(seconds / 60)m ago"
    }
}

// MARK: - Sync Status Pill
struct SyncStatusPill: View {
    let isOnline: Bool
    let lastSync: Date?
    let pendingCount: Int
    
    var body: some View {
        HStack(spacing: 6) {
            // Online/Offline indicator
            Image(systemName: isOnline ? "checkmark.icloud" : "icloud.slash")
                .font(.system(size: 11))
                .foregroundColor(isOnline ? HawalaTheme.Colors.textTertiary : HawalaTheme.Colors.error)
            
            if !isOnline {
                Text("Offline")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(HawalaTheme.Colors.error)
            } else if let lastSync = lastSync {
                Text(formatSyncTime(lastSync))
                    .font(.system(size: 10))
                    .foregroundColor(HawalaTheme.Colors.textTertiary)
            }
            
            // Pending operations badge
            if pendingCount > 0 {
                Text("\(pendingCount)")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundColor(.white)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 2)
                    .background(Capsule().fill(HawalaTheme.Colors.warning))
            }
        }
        .padding(.horizontal, HawalaTheme.Spacing.sm)
        .padding(.vertical, 4)
    }
    
    private func formatSyncTime(_ date: Date) -> String {
        let seconds = Int(Date().timeIntervalSince(date))
        if seconds < 60 { return "Synced" }
        if seconds < 3600 { return "\(seconds / 60)m ago" }
        return "\(seconds / 3600)h ago"
    }
}

// MARK: - Live Price Badge
/// Shows live price with real-time update indicator
struct LivePriceBadge: View {
    let chainId: String
    @StateObject private var webSocket = WebSocketPriceService.shared
    
    @State private var flashColor: Bool = false
    @State private var previousPrice: Double?
    
    var body: some View {
        HStack(spacing: 4) {
            if let update = webSocket.prices[chainId] {
                // Live indicator
                Circle()
                    .fill(HawalaTheme.Colors.success)
                    .frame(width: 6, height: 6)
                
                // Price
                Text(formatPrice(update.price))
                    .font(HawalaTheme.Typography.body)
                    .fontWeight(.medium)
                    .foregroundColor(priceColor)
                    .background(
                        RoundedRectangle(cornerRadius: 4)
                            .fill(flashColor ? priceColor.opacity(0.2) : Color.clear)
                    )
                
                // Change percentage
                if let percent = update.priceChangePercent24h {
                    Text(formatPercent(percent))
                        .font(HawalaTheme.Typography.caption)
                        .foregroundColor(percent >= 0 ? HawalaTheme.Colors.success : HawalaTheme.Colors.error)
                }
            } else {
                // Fallback - show placeholder or use cached price
                Text("--")
                    .font(HawalaTheme.Typography.body)
                    .foregroundColor(HawalaTheme.Colors.textTertiary)
            }
        }
        .onChange(of: webSocket.prices[chainId]?.price) { newPrice in
            guard let newPrice = newPrice else { return }
            
            // Flash effect on price change
            if let prev = previousPrice, prev != newPrice {
                withAnimation(.easeInOut(duration: 0.15)) {
                    flashColor = true
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                    withAnimation(.easeOut(duration: 0.3)) {
                        flashColor = false
                    }
                }
            }
            previousPrice = newPrice
        }
    }
    
    private var priceColor: Color {
        guard let update = webSocket.prices[chainId],
              let percent = update.priceChangePercent24h else {
            return HawalaTheme.Colors.textPrimary
        }
        return percent >= 0 ? HawalaTheme.Colors.success : HawalaTheme.Colors.error
    }
    
    private func formatPrice(_ price: Double) -> String {
        if price >= 1000 {
            return "$\(String(format: "%.2f", price))"
        } else if price >= 1 {
            return "$\(String(format: "%.4f", price))"
        } else {
            return "$\(String(format: "%.6f", price))"
        }
    }
    
    private func formatPercent(_ percent: Double) -> String {
        let sign = percent >= 0 ? "+" : ""
        return "\(sign)\(String(format: "%.2f", percent))%"
    }
}

// MARK: - WebSocket Connection Control
/// Control view for manually managing WebSocket connection
struct WebSocketConnectionControl: View {
    @StateObject private var webSocket = WebSocketPriceService.shared
    
    var body: some View {
        HStack(spacing: HawalaTheme.Spacing.md) {
            // Connection status
            HStack(spacing: HawalaTheme.Spacing.sm) {
                Image(systemName: webSocket.connectionState.statusIcon)
                    .foregroundColor(statusColor)
                
                VStack(alignment: .leading, spacing: 2) {
                    Text("Real-time Prices")
                        .font(HawalaTheme.Typography.bodySmall)
                        .foregroundColor(HawalaTheme.Colors.textPrimary)
                    
                    Text(webSocket.connectionState.statusText)
                        .font(HawalaTheme.Typography.caption)
                        .foregroundColor(HawalaTheme.Colors.textTertiary)
                }
            }
            
            Spacer()
            
            // Toggle button
            Button(action: toggleConnection) {
                Text(webSocket.connectionState.isConnected ? "Disconnect" : "Connect")
                    .font(HawalaTheme.Typography.caption)
                    .fontWeight(.medium)
                    .foregroundColor(webSocket.connectionState.isConnected ? HawalaTheme.Colors.error : HawalaTheme.Colors.accent)
                    .padding(.horizontal, HawalaTheme.Spacing.md)
                    .padding(.vertical, HawalaTheme.Spacing.sm)
                    .background(
                        Capsule()
                            .fill(webSocket.connectionState.isConnected ? 
                                  HawalaTheme.Colors.error.opacity(0.15) : 
                                  HawalaTheme.Colors.accent.opacity(0.15))
                    )
            }
            .buttonStyle(.plain)
        }
        .padding(HawalaTheme.Spacing.md)
        .background(HawalaTheme.Colors.backgroundSecondary)
        .clipShape(RoundedRectangle(cornerRadius: HawalaTheme.Radius.md, style: .continuous))
    }
    
    private var statusColor: Color {
        switch webSocket.connectionState {
        case .connected: return HawalaTheme.Colors.success
        case .connecting, .reconnecting: return HawalaTheme.Colors.warning
        case .disconnected: return HawalaTheme.Colors.textTertiary
        case .failed: return HawalaTheme.Colors.error
        }
    }
    
    private func toggleConnection() {
        if webSocket.connectionState.isConnected {
            webSocket.disconnect()
        } else {
            webSocket.connect()
        }
    }
}

// MARK: - Sync Settings Control
struct SyncSettingsControl: View {
    @StateObject private var syncService = BackendSyncService.shared
    
    var body: some View {
        VStack(alignment: .leading, spacing: HawalaTheme.Spacing.md) {
            // Header
            HStack {
                Image(systemName: "arrow.triangle.2.circlepath")
                    .foregroundColor(HawalaTheme.Colors.accent)
                
                Text("Background Sync")
                    .font(HawalaTheme.Typography.bodySmall)
                    .fontWeight(.medium)
                    .foregroundColor(HawalaTheme.Colors.textPrimary)
                
                Spacer()
                
                Toggle("", isOn: $syncService.autoSyncEnabled)
                    .toggleStyle(HawalaToggleStyle())
                    .labelsHidden()
            }
            
            // Status
            HStack(spacing: HawalaTheme.Spacing.sm) {
                Image(systemName: syncService.syncStatusIcon)
                    .font(.system(size: 12))
                    .foregroundColor(HawalaTheme.Colors.textTertiary)
                
                Text(syncService.overallSyncStatus)
                    .font(HawalaTheme.Typography.caption)
                    .foregroundColor(HawalaTheme.Colors.textTertiary)
                
                Spacer()
                
                if syncService.pendingOperationsCount > 0 {
                    Text("\(syncService.pendingOperationsCount) pending")
                        .font(HawalaTheme.Typography.caption)
                        .foregroundColor(HawalaTheme.Colors.warning)
                }
            }
            
            // Manual sync button
            Button(action: {
                Task { await syncService.syncAll() }
            }) {
                HStack {
                    Image(systemName: "arrow.clockwise")
                    Text("Sync Now")
                }
                .font(HawalaTheme.Typography.caption)
                .fontWeight(.medium)
                .foregroundColor(HawalaTheme.Colors.accent)
                .frame(maxWidth: .infinity)
                .padding(.vertical, HawalaTheme.Spacing.sm)
                .background(HawalaTheme.Colors.accentSubtle)
                .clipShape(RoundedRectangle(cornerRadius: HawalaTheme.Radius.sm, style: .continuous))
            }
            .buttonStyle(.plain)
            .disabled(syncService.syncStates.values.contains { $0.isSyncing })
        }
        .padding(HawalaTheme.Spacing.md)
        .background(HawalaTheme.Colors.backgroundSecondary)
        .clipShape(RoundedRectangle(cornerRadius: HawalaTheme.Radius.md, style: .continuous))
    }
}

// MARK: - Network Settings Section
/// Combined section for settings panel
struct NetworkSettingsSection: View {
    var body: some View {
        VStack(alignment: .leading, spacing: HawalaTheme.Spacing.lg) {
            Text("Network & Sync")
                .font(HawalaTheme.Typography.h3)
                .foregroundColor(HawalaTheme.Colors.textPrimary)
            
            WebSocketConnectionControl()
            SyncSettingsControl()
        }
    }
}

// MARK: - Preview
#if false // Disabled #Preview for command-line builds
#if false
#if false
#Preview {
    VStack(spacing: 20) {
        NetworkStatusBar()
        
        LivePriceBadge(chainId: "bitcoin")
        
        WebSocketConnectionControl()
            .padding()
        
        SyncSettingsControl()
            .padding()
    }
    .padding()
    .background(HawalaTheme.Colors.background)
}
#endif
#endif
#endif
