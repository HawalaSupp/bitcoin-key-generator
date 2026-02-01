import SwiftUI

/// Main notifications center view
struct NotificationsView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var notificationManager = NotificationManager.shared
    @State private var selectedTab = 0
    @State private var showAddAlert = false
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            headerView
            
            Divider()
            
            // Tab selector
            Picker("Tab", selection: $selectedTab) {
                Text("History").tag(0)
                Text("Price Alerts").tag(1)
                Text("Settings").tag(2)
            }
            .pickerStyle(.segmented)
            .padding()
            
            // Content
            TabView(selection: $selectedTab) {
                historyTab.tag(0)
                priceAlertsTab.tag(1)
                settingsTab.tag(2)
            }
            .tabViewStyle(.automatic)
        }
        .frame(minWidth: 500, idealWidth: 550, minHeight: 450, idealHeight: 500)
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
    
    private var headerView: some View {
        HStack {
            Button("Done") { dismiss() }
                .buttonStyle(.plain)
                .foregroundStyle(.blue)
            
            Spacer()
            
            HStack(spacing: 4) {
                Text("Notifications")
                    .font(.headline)
                
                if notificationManager.unreadCount > 0 {
                    Text("\(notificationManager.unreadCount)")
                        .font(.caption2)
                        .fontWeight(.semibold)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.red)
                        .foregroundStyle(.white)
                        .clipShape(Capsule())
                }
            }
            
            Spacer()
            
            if !notificationManager.isAuthorized {
                Button {
                    Task { _ = await notificationManager.requestAuthorization() }
                } label: {
                    Label("Enable", systemImage: "bell.badge")
                        .font(.caption)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
            }
        }
        .padding()
    }
    
    // MARK: - History Tab
    
    private var historyTab: some View {
        VStack(spacing: 0) {
            if notificationManager.notificationHistory.isEmpty {
                emptyHistoryView
            } else {
                HStack {
                    Button("Mark All Read") {
                        notificationManager.markAllAsRead()
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.blue)
                    .disabled(notificationManager.unreadCount == 0)
                    
                    Spacer()
                    
                    Button("Clear All") {
                        notificationManager.clearHistory()
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.red)
                }
                .padding(.horizontal)
                .padding(.vertical, 8)
                
                Divider()
                
                List(notificationManager.notificationHistory) { notification in
                    NotificationRow(notification: notification) {
                        notificationManager.markAsRead(notification)
                    }
                }
            }
        }
    }
    
    private var emptyHistoryView: some View {
        VStack(spacing: 12) {
            Image(systemName: "bell.slash")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)
            
            Text("No Notifications")
                .font(.headline)
            
            Text("You'll see transaction confirmations, price alerts, and security reminders here")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    // MARK: - Price Alerts Tab
    
    private var priceAlertsTab: some View {
        VStack(spacing: 0) {
            HStack {
                Text("\(notificationManager.priceAlerts.count) alerts")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                
                Spacer()
                
                Button {
                    showAddAlert = true
                } label: {
                    Label("Add Alert", systemImage: "plus")
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
            }
            .padding()
            
            Divider()
            
            if notificationManager.priceAlerts.isEmpty {
                emptyAlertsView
            } else {
                List {
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
    
    private var emptyAlertsView: some View {
        VStack(spacing: 12) {
            Image(systemName: "chart.line.uptrend.xyaxis")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)
            
            Text("No Price Alerts")
                .font(.headline)
            
            Text("Get notified when your favorite assets hit your target price")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
            
            Button {
                showAddAlert = true
            } label: {
                Label("Add Your First Alert", systemImage: "plus")
            }
            .buttonStyle(.borderedProminent)
            .padding(.top, 8)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    // MARK: - Settings Tab
    
    private var settingsTab: some View {
        Form {
            Section("Notification Types") {
                Toggle("Transaction Alerts", isOn: $notificationManager.settings.transactionAlerts)
                Toggle("Price Alerts", isOn: $notificationManager.settings.priceAlerts)
                Toggle("Security Reminders", isOn: $notificationManager.settings.securityReminders)
                Toggle("Staking Alerts", isOn: $notificationManager.settings.stakingAlerts)
            }
            
            Section("Delivery") {
                Toggle("Sound", isOn: $notificationManager.settings.soundEnabled)
                Toggle("Badge Count", isOn: $notificationManager.settings.badgeEnabled)
            }
            
            Section("Price Monitoring") {
                HStack {
                    Text("Status")
                    Spacer()
                    Text("Active")
                        .foregroundStyle(.green)
                }
                
                Button("Start Monitoring") {
                    notificationManager.startPriceMonitoring()
                }
                
                Button("Stop Monitoring") {
                    notificationManager.stopPriceMonitoring()
                }
                .foregroundStyle(.red)
            }
            
            Section("Test") {
                Button("Send Test Notification") {
                    Task {
                        await notificationManager.sendNotification(
                            type: .securityReminder,
                            title: "Test Notification",
                            body: "This is a test notification from Hawala"
                        )
                    }
                }
            }
        }
        .formStyle(.grouped)
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
            HStack(spacing: 12) {
                // Icon
                Image(systemName: notification.type.icon)
                    .font(.title2)
                    .foregroundStyle(iconColor)
                    .frame(width: 36)
                
                // Content
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(notification.title)
                            .font(.headline)
                            .fontWeight(notification.isRead ? .regular : .semibold)
                        
                        if !notification.isRead {
                            Circle()
                                .fill(.blue)
                                .frame(width: 8, height: 8)
                        }
                    }
                    
                    Text(notification.body)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                    
                    Text(notification.timestamp.formatted(date: .abbreviated, time: .shortened))
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
                
                Spacer()
            }
            .padding(.vertical, 4)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
    
    private var iconColor: Color {
        switch notification.type {
        case .transactionConfirmed: return .green
        case .transactionFailed: return .red
        case .priceAlert: return .orange
        case .securityReminder: return .blue
        case .stakingReward: return .purple
        }
    }
}

struct PriceAlertRow: View {
    let alert: PriceAlert
    let onToggle: () -> Void
    let onDelete: () -> Void
    
    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(alert.symbol)
                        .font(.headline)
                    
                    Image(systemName: alert.isAbove ? "arrow.up" : "arrow.down")
                        .foregroundStyle(alert.isAbove ? .green : .red)
                }
                
                Text(alert.description)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                
                if let triggered = alert.triggeredAt {
                    Text("Triggered \(triggered.formatted(date: .abbreviated, time: .shortened))")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }
            
            Spacer()
            
            Toggle("", isOn: Binding(
                get: { alert.isActive },
                set: { _ in onToggle() }
            ))
            .labelsHidden()
            
            Button(role: .destructive) {
                onDelete()
            } label: {
                Image(systemName: "trash")
                    .foregroundStyle(.red)
            }
            .buttonStyle(.plain)
        }
        .padding(.vertical, 4)
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
        VStack(spacing: 20) {
            // Header
            HStack {
                Button("Cancel") { onCancel() }
                    .buttonStyle(.plain)
                
                Spacer()
                
                Text("Add Price Alert")
                    .font(.headline)
                
                Spacer()
                
                Button("Add") {
                    if let price = Double(priceInput) {
                        let symbol = assets.first { $0.0 == selectedAsset }?.1 ?? "BTC"
                        onAdd(selectedAsset, symbol, price, isAbove)
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(Double(priceInput) == nil)
            }
            .padding()
            
            Divider()
            
            // Asset picker
            VStack(alignment: .leading, spacing: 8) {
                Text("Asset")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                
                Picker("Asset", selection: $selectedAsset) {
                    ForEach(assets, id: \.0) { asset in
                        Text("\(asset.1) - \(asset.0.capitalized)").tag(asset.0)
                    }
                }
                .pickerStyle(.menu)
            }
            .padding(.horizontal)
            
            // Direction
            VStack(alignment: .leading, spacing: 8) {
                Text("Alert when price goes")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                
                Picker("Direction", selection: $isAbove) {
                    Label("Above", systemImage: "arrow.up").tag(true)
                    Label("Below", systemImage: "arrow.down").tag(false)
                }
                .pickerStyle(.segmented)
            }
            .padding(.horizontal)
            
            // Price input
            VStack(alignment: .leading, spacing: 8) {
                Text("Target Price (USD)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                
                HStack {
                    Text("$")
                        .foregroundStyle(.secondary)
                    TextField("0.00", text: $priceInput)
                        .textFieldStyle(.roundedBorder)
                }
            }
            .padding(.horizontal)
            
            Spacer()
        }
        .frame(width: 350, height: 350)
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
