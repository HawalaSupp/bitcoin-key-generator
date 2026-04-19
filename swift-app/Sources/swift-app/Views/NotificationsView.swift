import SwiftUI

/// Main notifications center view
struct NotificationsView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var notificationManager = NotificationManager.shared
    @State private var selectedTab = 0
    @State private var showAddAlert = false
    
    var body: some View {
        HawalaSheetShell(title: "Notifications", width: 520, height: 520) {
            // Auth banner
            if !notificationManager.isAuthorized {
                HStack(spacing: 8) {
                    Image(systemName: "bell.slash")
                        .font(.system(size: 12))
                        .foregroundColor(Color(red: 1, green: 0.84, blue: 0.04))
                    Text("Notifications disabled")
                        .font(.system(size: 11))
                        .foregroundColor(Color(red: 1, green: 0.84, blue: 0.04).opacity(0.8))
                    Spacer()
                    Button("Enable") {
                        Task { _ = await notificationManager.requestAuthorization() }
                    }
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(.white)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(Color.white.opacity(0.12))
                    .clipShape(Capsule())
                    .buttonStyle(.plain)
                }
                .padding(10)
                .background(Color(red: 1, green: 0.84, blue: 0.04).opacity(0.08))
                .clipShape(RoundedRectangle(cornerRadius: 8))
            }

            // Unread badge
            if notificationManager.unreadCount > 0 {
                HStack(spacing: 4) {
                    Text("\(notificationManager.unreadCount) unread")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(Color(red: 1, green: 0.27, blue: 0.23))
                    Spacer()
                }
            }

            // Tab selector
            Picker("Tab", selection: $selectedTab) {
                Text("History").tag(0)
                Text("Price Alerts").tag(1)
                Text("Settings").tag(2)
            }
            .pickerStyle(.segmented)
            
            // Content
            switch selectedTab {
            case 0: historyTab
            case 1: priceAlertsTab
            case 2: settingsTab
            default: EmptyView()
            }
        }
        .sheet(isPresented: $showAddAlert) {
            AddPriceAlertSheet(onAdd: { asset, symbol, price, isAbove in
                notificationManager.addPriceAlert(
                    asset: asset,
                    symbol: symbol,
                    targetPrice: price,
                    isAbove: isAbove
                )
                showAddAlert = false
            }, onCancel: {
                showAddAlert = false
            })
        }
        .task {
            if !notificationManager.isAuthorized {
                _ = await notificationManager.requestAuthorization()
            }
        }
    }
    
    // MARK: - History Tab
    
    private var historyTab: some View {
        VStack(spacing: 8) {
            if notificationManager.notificationHistory.isEmpty {
                emptyHistoryView
            } else {
                HStack {
                    Button("Mark All Read") {
                        notificationManager.markAllAsRead()
                    }
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(Color.white.opacity(0.5))
                    .buttonStyle(.plain)
                    .disabled(notificationManager.unreadCount == 0)
                    
                    Spacer()
                    
                    Button("Clear All") {
                        notificationManager.clearHistory()
                    }
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(Color(red: 1, green: 0.27, blue: 0.23))
                    .buttonStyle(.plain)
                }

                ScrollView {
                    LazyVStack(spacing: 6) {
                        ForEach(notificationManager.notificationHistory) { notification in
                            NotificationRow(notification: notification) {
                                notificationManager.markAsRead(notification)
                            }
                        }
                    }
                }
            }
        }
    }
    
    private var emptyHistoryView: some View {
        VStack(spacing: 10) {
            Image(systemName: "bell.slash")
                .font(.system(size: 32))
                .foregroundColor(.white.opacity(0.15))
            Text("No Notifications")
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(.white.opacity(0.5))
            Text("You'll see transaction confirmations, price alerts, and security reminders here")
                .font(.system(size: 11))
                .foregroundColor(.white.opacity(0.3))
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 20)
    }
    
    // MARK: - Price Alerts Tab
    
    private var priceAlertsTab: some View {
        VStack(spacing: 8) {
            HStack {
                Text("\(notificationManager.priceAlerts.count) alerts")
                    .font(.system(size: 10))
                    .foregroundColor(.white.opacity(0.35))
                Spacer()
                Button { showAddAlert = true } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "plus")
                            .font(.system(size: 9))
                        Text("Add Alert")
                            .font(.system(size: 10, weight: .medium))
                    }
                    .foregroundColor(Color.white.opacity(0.5))
                }
                .buttonStyle(.plain)
            }

            if notificationManager.priceAlerts.isEmpty {
                emptyAlertsView
            } else {
                ScrollView {
                    LazyVStack(spacing: 6) {
                        ForEach(notificationManager.priceAlerts) { alert in
                            PriceAlertRow(alert: alert) {
                                notificationManager.togglePriceAlert(alert)
                            } onDelete: {
                                notificationManager.removePriceAlert(alert)
                            }
                        }
                    }
                }
            }
        }
    }
    
    private var emptyAlertsView: some View {
        VStack(spacing: 10) {
            Image(systemName: "chart.line.uptrend.xyaxis")
                .font(.system(size: 32))
                .foregroundColor(.white.opacity(0.15))
            Text("No Price Alerts")
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(.white.opacity(0.5))
            Text("Get notified when your favorite assets hit your target price")
                .font(.system(size: 11))
                .foregroundColor(.white.opacity(0.3))
                .multilineTextAlignment(.center)
            HawalaActionButton(icon: "plus.circle", label: "Add Your First Alert", style: .primary) {
                showAddAlert = true
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 20)
    }
    
    // MARK: - Settings Tab
    
    private var settingsTab: some View {
        VStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 8) {
                HawalaOverlaySectionHeader(icon: "bell.fill", title: "Notification Types")
                HawalaToggleRow(icon: "arrow.left.arrow.right", label: "Transaction Alerts", isOn: $notificationManager.settings.transactionAlerts)
                HawalaToggleRow(icon: "chart.line.uptrend.xyaxis", label: "Price Alerts", isOn: $notificationManager.settings.priceAlerts)
                HawalaToggleRow(icon: "shield.fill", label: "Security Reminders", isOn: $notificationManager.settings.securityReminders)
                HawalaToggleRow(icon: "gift.fill", label: "Staking Alerts", isOn: $notificationManager.settings.stakingAlerts)
            }
            .hawalaSectionCard()

            VStack(alignment: .leading, spacing: 8) {
                HawalaOverlaySectionHeader(icon: "speaker.wave.2.fill", title: "Delivery")
                HawalaToggleRow(icon: "speaker.fill", label: "Sound", isOn: $notificationManager.settings.soundEnabled)
                HawalaToggleRow(icon: "app.badge", label: "Badge Count", isOn: $notificationManager.settings.badgeEnabled)
            }
            .hawalaSectionCard()

            VStack(alignment: .leading, spacing: 8) {
                HawalaOverlaySectionHeader(icon: "chart.bar.fill", title: "Price Monitoring")
                HStack {
                    Text("Status")
                        .font(.system(size: 11))
                        .foregroundColor(.white.opacity(0.5))
                    Spacer()
                    HStack(spacing: 4) {
                        Circle().fill(Color(red: 0.20, green: 0.84, blue: 0.29)).frame(width: 6, height: 6)
                        Text("Active")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundColor(Color(red: 0.20, green: 0.84, blue: 0.29))
                    }
                }
                HStack(spacing: 8) {
                    Button("Start") { notificationManager.startPriceMonitoring() }
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(Color.white.opacity(0.5))
                        .buttonStyle(.plain)
                    Button("Stop") { notificationManager.stopPriceMonitoring() }
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(Color(red: 1, green: 0.27, blue: 0.23))
                        .buttonStyle(.plain)
                }
                Button("Send Test Notification") {
                    Task {
                        await notificationManager.sendNotification(
                            type: .securityReminder,
                            title: "Test Notification",
                            body: "This is a test notification from Hawala"
                        )
                    }
                }
                .font(.system(size: 10, weight: .medium))
                .foregroundColor(.white.opacity(0.5))
                .buttonStyle(.plain)
            }
            .hawalaSectionCard()
        }
        .onChange(of: notificationManager.settings.transactionAlerts) { _ in
            notificationManager.saveSettings()
        }
        .onChange(of: notificationManager.settings.priceAlerts) { _ in
            notificationManager.saveSettings()
        }
        .onChange(of: notificationManager.settings.securityReminders) { _ in
            notificationManager.saveSettings()
        }
        .onChange(of: notificationManager.settings.stakingAlerts) { _ in
            notificationManager.saveSettings()
        }
        .onChange(of: notificationManager.settings.soundEnabled) { _ in
            notificationManager.saveSettings()
        }
        .onChange(of: notificationManager.settings.badgeEnabled) { _ in
            notificationManager.saveSettings()
        }
    }
}

// MARK: - Supporting Views

struct NotificationRow: View {
    let notification: NotificationRecord
    let onTap: () -> Void
    
    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 10) {
                Image(systemName: notification.type.icon)
                    .font(.system(size: 14))
                    .foregroundColor(iconColor)
                    .frame(width: 28, height: 28)
                    .background(iconColor.opacity(0.1))
                    .clipShape(Circle())
                
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 4) {
                        Text(notification.title)
                            .font(.system(size: 12, weight: notification.isRead ? .regular : .semibold))
                            .foregroundColor(.white.opacity(notification.isRead ? 0.5 : 0.85))
                        
                        if !notification.isRead {
                            Circle()
                                .fill(Color.white.opacity(0.12))
                                .frame(width: 6, height: 6)
                        }
                    }
                    
                    Text(notification.body)
                        .font(.system(size: 10))
                        .foregroundColor(.white.opacity(0.35))
                        .lineLimit(2)
                    
                    Text(notification.timestamp.formatted(date: .abbreviated, time: .shortened))
                        .font(.system(size: 9))
                        .foregroundColor(.white.opacity(0.2))
                }
                
                Spacer()
            }
            .padding(8)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(notification.isRead ? Color.clear : Color.white.opacity(0.02))
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
    
    private var iconColor: Color {
        switch notification.type {
        case .transactionConfirmed: return Color(red: 0.20, green: 0.84, blue: 0.29)
        case .transactionFailed: return Color(red: 1, green: 0.27, blue: 0.23)
        case .priceAlert: return Color(red: 1, green: 0.84, blue: 0.04)
        case .securityReminder: return Color.white.opacity(0.5)
        case .stakingReward: return .purple
        }
    }
}

struct PriceAlertRow: View {
    let alert: PriceAlert
    let onToggle: () -> Void
    let onDelete: () -> Void
    
    var body: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    Text(alert.symbol)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(.white.opacity(0.85))
                    Image(systemName: alert.isAbove ? "arrow.up" : "arrow.down")
                        .font(.system(size: 10))
                        .foregroundColor(alert.isAbove ? Color(red: 0.20, green: 0.84, blue: 0.29) : Color(red: 1, green: 0.27, blue: 0.23))
                }
                Text(alert.description)
                    .font(.system(size: 10))
                    .foregroundColor(.white.opacity(0.35))
                if let triggered = alert.triggeredAt {
                    Text("Triggered \(triggered.formatted(date: .abbreviated, time: .shortened))")
                        .font(.system(size: 9))
                        .foregroundColor(.white.opacity(0.2))
                }
            }
            
            Spacer()
            
            Toggle("", isOn: Binding(
                get: { alert.isActive },
                set: { _ in onToggle() }
            ))
            .labelsHidden()
            .toggleStyle(.switch)
            .tint(Color.white)
            
            Button(role: .destructive) { onDelete() } label: {
                Image(systemName: "trash")
                    .font(.system(size: 10))
                    .foregroundColor(Color(red: 1, green: 0.27, blue: 0.23).opacity(0.6))
            }
            .buttonStyle(.plain)
        }
        .padding(8)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.white.opacity(0.03))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .strokeBorder(.white.opacity(0.04), lineWidth: 1)
                )
        )
    }
}

struct AddPriceAlertSheet: View {
    let onAdd: (String, String, Double, Bool) -> Void
    let onCancel: () -> Void
    
    @State private var selectedAsset = "bitcoin"
    @State private var priceInput = ""
    @State private var isAbove = true
    
    private let assets = [
        ("bitcoin", "BTC"),
        ("ethereum", "ETH"),
        ("solana", "SOL"),
        ("binancecoin", "BNB"),
        ("litecoin", "LTC"),
        ("ripple", "XRP"),
        ("monero", "XMR")
    ]
    
    var body: some View {
        HawalaSheetShell(title: "Add Price Alert", width: 380, height: 360) {
            VStack(alignment: .leading, spacing: 8) {
                HawalaOverlaySectionHeader(icon: "bitcoinsign.circle", title: "Asset")
                Picker("Asset", selection: $selectedAsset) {
                    ForEach(assets, id: \.0) { asset in
                        Text("\(asset.1) - \(asset.0.capitalized)").tag(asset.0)
                    }
                }
                .pickerStyle(.menu)
            }
            .hawalaSectionCard()

            VStack(alignment: .leading, spacing: 8) {
                HawalaOverlaySectionHeader(icon: "arrow.up.arrow.down", title: "Direction")
                Picker("Direction", selection: $isAbove) {
                    Label("Above", systemImage: "arrow.up").tag(true)
                    Label("Below", systemImage: "arrow.down").tag(false)
                }
                .pickerStyle(.segmented)
            }
            .hawalaSectionCard()

            VStack(alignment: .leading, spacing: 8) {
                HawalaOverlaySectionHeader(icon: "dollarsign.circle", title: "Target Price (USD)")
                HStack(spacing: 4) {
                    Text("$")
                        .font(.system(size: 13))
                        .foregroundColor(.white.opacity(0.35))
                    TextField("0.00", text: $priceInput)
                        .font(.system(size: 13, design: .monospaced))
                        .foregroundColor(.white.opacity(0.85))
                        .textFieldStyle(.plain)
                }
                .padding(8)
                .background(Color.white.opacity(0.04))
                .clipShape(RoundedRectangle(cornerRadius: 8))
            }
            .hawalaSectionCard()

            HStack(spacing: 10) {
                HawalaActionButton(icon: "xmark", label: "Cancel", style: .secondary) {
                    onCancel()
                }
                HawalaActionButton(icon: "plus.circle", label: "Add Alert", style: .primary) {
                    if let price = Double(priceInput) {
                        let symbol = assets.first { $0.0 == selectedAsset }?.1 ?? "BTC"
                        onAdd(selectedAsset, symbol, price, isAbove)
                    }
                }
            }
        }
    }
}

#if false // Disabled #Preview for command-line builds
#if false
#if false
#Preview {
    NotificationsView()
}
#endif
#endif
#endif
