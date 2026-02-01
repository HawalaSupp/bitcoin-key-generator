import SwiftUI

// MARK: - Price Alerts View
/// Create and manage price alerts for cryptocurrencies
struct PriceAlertsView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var isLoading = false
    @State private var error: String?
    @State private var appearAnimation = false
    
    // Alert creation
    @State private var showCreateSheet = false
    @State private var selectedSymbol = "BTC"
    @State private var alertType: HawalaBridge.AlertType = .above
    @State private var targetValue = ""
    @State private var alertNote = ""
    @State private var repeatAlert = false
    
    // Data
    @State private var alerts: [HawalaBridge.PriceAlert] = []
    @State private var stats: HawalaBridge.AlertStats?
    @State private var currentPrices: [String: HawalaBridge.PriceData] = [:]
    
    private let supportedSymbols = ["BTC", "ETH", "SOL", "XRP", "LTC", "DOGE", "ADA", "AVAX", "DOT", "MATIC"]
    
    var body: some View {
        ZStack {
            HawalaTheme.Colors.background
                .ignoresSafeArea()
            
            VStack(spacing: 0) {
                // Header
                headerView
                
                // Stats bar
                if let stats = stats {
                    statsBar(stats: stats)
                }
                
                Divider()
                    .background(HawalaTheme.Colors.divider)
                
                // Content
                if isLoading && alerts.isEmpty {
                    loadingView
                } else if alerts.isEmpty {
                    emptyStateView
                } else {
                    alertsListView
                }
            }
            
            // FAB
            VStack {
                Spacer()
                HStack {
                    Spacer()
                    createAlertButton
                        .padding()
                }
            }
            
            // Error toast
            if let error = error {
                VStack {
                    Spacer()
                    errorToast(message: error)
                        .padding(.bottom, 80)
                }
            }
        }
        .frame(minWidth: 550, idealWidth: 650, minHeight: 500, idealHeight: 650)
        .onAppear {
            withAnimation(HawalaTheme.Animation.spring) {
                appearAnimation = true
            }
            Task {
                await fetchStats()
                await fetchPrices()
            }
        }
        .sheet(isPresented: $showCreateSheet) {
            createAlertSheet
        }
    }
    
    // MARK: - Header
    
    private var headerView: some View {
        HStack {
            Button(action: { dismiss() }) {
                Image(systemName: "xmark")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(HawalaTheme.Colors.textSecondary)
                    .frame(width: 32, height: 32)
                    .background(HawalaTheme.Colors.backgroundTertiary)
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)
            
            Spacer()
            
            VStack(spacing: 2) {
                Text("Price Alerts")
                    .font(HawalaTheme.Typography.h3)
                    .foregroundColor(HawalaTheme.Colors.textPrimary)
                
                Text("Get notified on price movements")
                    .font(HawalaTheme.Typography.caption)
                    .foregroundColor(HawalaTheme.Colors.textSecondary)
            }
            
            Spacer()
            
            Button(action: { Task { await fetchStats() } }) {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(HawalaTheme.Colors.textSecondary)
                    .frame(width: 32, height: 32)
                    .background(HawalaTheme.Colors.backgroundTertiary)
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)
            .disabled(isLoading)
        }
        .padding()
    }
    
    // MARK: - Stats Bar
    
    private func statsBar(stats: HawalaBridge.AlertStats) -> some View {
        HStack(spacing: HawalaTheme.Spacing.lg) {
            statItem(value: "\(stats.active)", label: "Active", color: HawalaTheme.Colors.success)
            
            Divider()
                .frame(height: 30)
            
            statItem(value: "\(stats.triggered)", label: "Triggered", color: HawalaTheme.Colors.warning)
            
            Divider()
                .frame(height: 30)
            
            statItem(value: "\(stats.total)", label: "Total", color: HawalaTheme.Colors.textSecondary)
            
            Divider()
                .frame(height: 30)
            
            statItem(value: "\(stats.bySymbol.count)", label: "Symbols", color: HawalaTheme.Colors.accent)
        }
        .padding(.horizontal, HawalaTheme.Spacing.lg)
        .padding(.vertical, HawalaTheme.Spacing.md)
        .background(HawalaTheme.Colors.backgroundSecondary)
    }
    
    private func statItem(value: String, label: String, color: Color) -> some View {
        VStack(spacing: 2) {
            Text(value)
                .font(HawalaTheme.Typography.h3)
                .foregroundColor(color)
            
            Text(label)
                .font(HawalaTheme.Typography.caption)
                .foregroundColor(HawalaTheme.Colors.textTertiary)
        }
    }
    
    // MARK: - Alerts List
    
    private var alertsListView: some View {
        ScrollView(showsIndicators: false) {
            LazyVStack(spacing: HawalaTheme.Spacing.sm) {
                // Current prices section
                pricesOverviewSection
                
                // Active alerts
                Text("ACTIVE ALERTS")
                    .font(HawalaTheme.Typography.label)
                    .foregroundColor(HawalaTheme.Colors.textTertiary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.top, HawalaTheme.Spacing.md)
                
                ForEach(alerts.filter { $0.status == .active }, id: \.id) { alert in
                    alertCard(alert: alert)
                }
                
                // Triggered alerts
                let triggeredAlerts = alerts.filter { $0.status == .triggered }
                if !triggeredAlerts.isEmpty {
                    Text("TRIGGERED")
                        .font(HawalaTheme.Typography.label)
                        .foregroundColor(HawalaTheme.Colors.textTertiary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.top, HawalaTheme.Spacing.md)
                    
                    ForEach(triggeredAlerts, id: \.id) { alert in
                        alertCard(alert: alert)
                    }
                }
            }
            .padding(.horizontal, HawalaTheme.Spacing.lg)
            .padding(.vertical, HawalaTheme.Spacing.md)
            .padding(.bottom, 80)
        }
    }
    
    // MARK: - Prices Overview
    
    private var pricesOverviewSection: some View {
        VStack(alignment: .leading, spacing: HawalaTheme.Spacing.sm) {
            Text("CURRENT PRICES")
                .font(HawalaTheme.Typography.label)
                .foregroundColor(HawalaTheme.Colors.textTertiary)
            
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: HawalaTheme.Spacing.md) {
                    ForEach(Array(currentPrices.keys.sorted()), id: \.self) { symbol in
                        if let price = currentPrices[symbol] {
                            priceCard(symbol: symbol, price: price)
                        }
                    }
                }
            }
        }
    }
    
    private func priceCard(symbol: String, price: HawalaBridge.PriceData) -> some View {
        VStack(alignment: .leading, spacing: HawalaTheme.Spacing.xs) {
            HStack {
                cryptoIcon(symbol)
                Text(symbol)
                    .font(HawalaTheme.Typography.captionBold)
                    .foregroundColor(HawalaTheme.Colors.textPrimary)
            }
            
            Text(formatPrice(price.price))
                .font(HawalaTheme.Typography.h4)
                .foregroundColor(HawalaTheme.Colors.textPrimary)
            
            HStack(spacing: 4) {
                Image(systemName: price.change24h >= 0 ? "arrow.up.right" : "arrow.down.right")
                    .font(.system(size: 10))
                Text(String(format: "%.2f%%", abs(price.change24hPercent)))
                    .font(HawalaTheme.Typography.label)
            }
            .foregroundColor(price.change24h >= 0 ? HawalaTheme.Colors.success : HawalaTheme.Colors.error)
        }
        .padding(HawalaTheme.Spacing.md)
        .background(HawalaTheme.Colors.backgroundSecondary)
        .clipShape(RoundedRectangle(cornerRadius: HawalaTheme.Radius.md))
    }
    
    private func cryptoIcon(_ symbol: String) -> some View {
        let color: Color = {
            switch symbol {
            case "BTC": return HawalaTheme.Colors.bitcoin
            case "ETH": return HawalaTheme.Colors.ethereum
            case "SOL": return HawalaTheme.Colors.solana
            case "XRP": return Color(hex: "23292F")
            case "LTC": return HawalaTheme.Colors.litecoin
            case "DOGE": return Color(hex: "C2A633")
            case "ADA": return Color(hex: "0033AD")
            case "AVAX": return Color(hex: "E84142")
            case "DOT": return Color(hex: "E6007A")
            case "MATIC": return Color(hex: "8247E5")
            default: return HawalaTheme.Colors.textSecondary
            }
        }()
        
        return Circle()
            .fill(color.opacity(0.2))
            .frame(width: 24, height: 24)
            .overlay(
                Text(String(symbol.prefix(1)))
                    .font(HawalaTheme.Typography.label)
                    .foregroundColor(color)
            )
    }
    
    // MARK: - Alert Card
    
    private func alertCard(alert: HawalaBridge.PriceAlert) -> some View {
        VStack(spacing: HawalaTheme.Spacing.md) {
            HStack {
                // Symbol
                HStack(spacing: HawalaTheme.Spacing.sm) {
                    cryptoIcon(alert.symbol)
                    
                    VStack(alignment: .leading, spacing: 2) {
                        Text(alert.symbol)
                            .font(HawalaTheme.Typography.h4)
                            .foregroundColor(HawalaTheme.Colors.textPrimary)
                        
                        Text(alertTypeDescription(alert.alertType))
                            .font(HawalaTheme.Typography.caption)
                            .foregroundColor(HawalaTheme.Colors.textSecondary)
                    }
                }
                
                Spacer()
                
                // Target
                VStack(alignment: .trailing, spacing: 2) {
                    Text(formatPrice(alert.targetValue))
                        .font(HawalaTheme.Typography.h4)
                        .foregroundColor(targetColor(alert))
                    
                    Text("Target")
                        .font(HawalaTheme.Typography.caption)
                        .foregroundColor(HawalaTheme.Colors.textTertiary)
                }
                
                // Status badge
                statusBadge(alert.status)
            }
            
            // Progress towards target (for active alerts)
            if alert.status == .active, let priceData = currentPrices[alert.symbol] {
                alertProgressBar(alert: alert, currentPrice: priceData.price)
            }
            
            // Note if present
            if let note = alert.note, !note.isEmpty {
                HStack {
                    Image(systemName: "note.text")
                        .font(.system(size: 12))
                        .foregroundColor(HawalaTheme.Colors.textTertiary)
                    
                    Text(note)
                        .font(HawalaTheme.Typography.caption)
                        .foregroundColor(HawalaTheme.Colors.textSecondary)
                        .lineLimit(1)
                    
                    Spacer()
                }
            }
            
            // Triggered info
            if alert.status == .triggered, let triggeredPrice = alert.triggeredPrice, let triggeredAt = alert.triggeredAt {
                HStack {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(HawalaTheme.Colors.success)
                    
                    Text("Triggered at \(formatPrice(triggeredPrice))")
                        .font(HawalaTheme.Typography.caption)
                        .foregroundColor(HawalaTheme.Colors.success)
                    
                    Spacer()
                    
                    Text(formatTimestamp(triggeredAt))
                        .font(HawalaTheme.Typography.caption)
                        .foregroundColor(HawalaTheme.Colors.textTertiary)
                }
            }
            
            // Repeat indicator
            if alert.repeat {
                HStack {
                    Image(systemName: "repeat")
                        .font(.system(size: 10))
                    Text("Repeating")
                        .font(HawalaTheme.Typography.caption)
                }
                .foregroundColor(HawalaTheme.Colors.info)
            }
        }
        .padding(HawalaTheme.Spacing.md)
        .background(HawalaTheme.Colors.backgroundSecondary)
        .clipShape(RoundedRectangle(cornerRadius: HawalaTheme.Radius.md))
        .overlay(
            RoundedRectangle(cornerRadius: HawalaTheme.Radius.md)
                .strokeBorder(statusBorderColor(alert.status), lineWidth: 1)
        )
    }
    
    private func alertTypeDescription(_ type: HawalaBridge.AlertType) -> String {
        switch type {
        case .above: return "Price goes above"
        case .below: return "Price goes below"
        case .percentIncrease: return "Increases by %"
        case .percentDecrease: return "Decreases by %"
        case .percentChange: return "Changes by %"
        }
    }
    
    private func targetColor(_ alert: HawalaBridge.PriceAlert) -> Color {
        switch alert.alertType {
        case .above, .percentIncrease:
            return HawalaTheme.Colors.success
        case .below, .percentDecrease:
            return HawalaTheme.Colors.error
        case .percentChange:
            return HawalaTheme.Colors.warning
        }
    }
    
    private func statusBadge(_ status: HawalaBridge.AlertStatus) -> some View {
        let (text, color): (String, Color) = {
            switch status {
            case .active: return ("Active", HawalaTheme.Colors.success)
            case .triggered: return ("Triggered", HawalaTheme.Colors.warning)
            case .paused: return ("Paused", HawalaTheme.Colors.textTertiary)
            case .expired: return ("Expired", HawalaTheme.Colors.error)
            case .cancelled: return ("Cancelled", HawalaTheme.Colors.textTertiary)
            }
        }()
        
        return Text(text)
            .font(HawalaTheme.Typography.label)
            .foregroundColor(color)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(color.opacity(0.15))
            .clipShape(Capsule())
    }
    
    private func statusBorderColor(_ status: HawalaBridge.AlertStatus) -> Color {
        switch status {
        case .active: return HawalaTheme.Colors.success.opacity(0.3)
        case .triggered: return HawalaTheme.Colors.warning.opacity(0.3)
        default: return HawalaTheme.Colors.border
        }
    }
    
    private func alertProgressBar(alert: HawalaBridge.PriceAlert, currentPrice: Double) -> some View {
        let progress: Double = {
            switch alert.alertType {
            case .above:
                guard alert.targetValue > currentPrice else { return 1.0 }
                let basePrice = alert.basePrice ?? currentPrice * 0.9
                return (currentPrice - basePrice) / (alert.targetValue - basePrice)
            case .below:
                guard currentPrice > alert.targetValue else { return 1.0 }
                let basePrice = alert.basePrice ?? currentPrice * 1.1
                return (basePrice - currentPrice) / (basePrice - alert.targetValue)
            default:
                return 0.5
            }
        }()
        
        return VStack(spacing: 4) {
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 2)
                        .fill(HawalaTheme.Colors.backgroundTertiary)
                        .frame(height: 4)
                    
                    RoundedRectangle(cornerRadius: 2)
                        .fill(targetColor(alert))
                        .frame(width: geometry.size.width * max(0, min(1, progress)), height: 4)
                }
            }
            .frame(height: 4)
            
            HStack {
                Text("Current: \(formatPrice(currentPrice))")
                    .font(HawalaTheme.Typography.caption)
                    .foregroundColor(HawalaTheme.Colors.textSecondary)
                
                Spacer()
                
                Text("\(Int(progress * 100))%")
                    .font(HawalaTheme.Typography.caption)
                    .foregroundColor(HawalaTheme.Colors.textTertiary)
            }
        }
    }
    
    // MARK: - Empty State
    
    private var emptyStateView: some View {
        VStack(spacing: HawalaTheme.Spacing.lg) {
            Spacer()
            
            Image(systemName: "bell.badge")
                .font(.system(size: 48))
                .foregroundColor(HawalaTheme.Colors.textTertiary)
            
            VStack(spacing: HawalaTheme.Spacing.sm) {
                Text("No Price Alerts")
                    .font(HawalaTheme.Typography.h3)
                    .foregroundColor(HawalaTheme.Colors.textPrimary)
                
                Text("Create alerts to get notified when prices reach your targets")
                    .font(HawalaTheme.Typography.body)
                    .foregroundColor(HawalaTheme.Colors.textSecondary)
                    .multilineTextAlignment(.center)
            }
            
            Button(action: { showCreateSheet = true }) {
                HStack {
                    Image(systemName: "plus")
                    Text("Create Your First Alert")
                }
                .font(HawalaTheme.Typography.captionBold)
                .foregroundColor(.white)
                .padding(.horizontal, HawalaTheme.Spacing.lg)
                .padding(.vertical, HawalaTheme.Spacing.md)
                .background(HawalaTheme.Colors.accent)
                .clipShape(RoundedRectangle(cornerRadius: HawalaTheme.Radius.md))
            }
            .buttonStyle(.plain)
            
            Spacer()
        }
        .padding()
    }
    
    // MARK: - Loading
    
    private var loadingView: some View {
        VStack {
            Spacer()
            ProgressView()
                .scaleEffect(1.5)
            Text("Loading alerts...")
                .font(HawalaTheme.Typography.caption)
                .foregroundColor(HawalaTheme.Colors.textSecondary)
                .padding(.top)
            Spacer()
        }
    }
    
    // MARK: - Create Alert Button
    
    private var createAlertButton: some View {
        Button(action: { showCreateSheet = true }) {
            Image(systemName: "plus")
                .font(.system(size: 20, weight: .semibold))
                .foregroundColor(.white)
                .frame(width: 56, height: 56)
                .background(HawalaTheme.Colors.accent)
                .clipShape(Circle())
                .shadow(color: HawalaTheme.Colors.accent.opacity(0.4), radius: 8, y: 4)
        }
        .buttonStyle(.plain)
    }
    
    // MARK: - Create Alert Sheet
    
    private var createAlertSheet: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Button("Cancel") { showCreateSheet = false }
                    .buttonStyle(.plain)
                    .foregroundColor(HawalaTheme.Colors.textSecondary)
                
                Spacer()
                
                Text("Create Alert")
                    .font(HawalaTheme.Typography.h4)
                
                Spacer()
                
                Button("Create") {
                    Task { await createAlert() }
                }
                .buttonStyle(.plain)
                .foregroundColor(HawalaTheme.Colors.accent)
                .disabled(targetValue.isEmpty)
            }
            .padding()
            
            Divider()
            
            ScrollView {
                VStack(spacing: HawalaTheme.Spacing.lg) {
                    // Symbol selector
                    VStack(alignment: .leading, spacing: HawalaTheme.Spacing.sm) {
                        Text("CRYPTOCURRENCY")
                            .font(HawalaTheme.Typography.label)
                            .foregroundColor(HawalaTheme.Colors.textTertiary)
                        
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: HawalaTheme.Spacing.sm) {
                                ForEach(supportedSymbols, id: \.self) { symbol in
                                    Button(action: { selectedSymbol = symbol }) {
                                        HStack(spacing: 4) {
                                            cryptoIcon(symbol)
                                            Text(symbol)
                                                .font(HawalaTheme.Typography.captionBold)
                                        }
                                        .foregroundColor(selectedSymbol == symbol ? .white : HawalaTheme.Colors.textSecondary)
                                        .padding(.horizontal, HawalaTheme.Spacing.md)
                                        .padding(.vertical, HawalaTheme.Spacing.sm)
                                        .background(selectedSymbol == symbol ? HawalaTheme.Colors.accent : HawalaTheme.Colors.backgroundTertiary)
                                        .clipShape(Capsule())
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }
                        
                        // Current price
                        if let price = currentPrices[selectedSymbol] {
                            HStack {
                                Text("Current price:")
                                    .font(HawalaTheme.Typography.caption)
                                    .foregroundColor(HawalaTheme.Colors.textSecondary)
                                
                                Text(formatPrice(price.price))
                                    .font(HawalaTheme.Typography.captionBold)
                                    .foregroundColor(HawalaTheme.Colors.textPrimary)
                            }
                        }
                    }
                    
                    // Alert type
                    VStack(alignment: .leading, spacing: HawalaTheme.Spacing.sm) {
                        Text("ALERT TYPE")
                            .font(HawalaTheme.Typography.label)
                            .foregroundColor(HawalaTheme.Colors.textTertiary)
                        
                        VStack(spacing: HawalaTheme.Spacing.sm) {
                            alertTypeButton(.above, icon: "arrow.up", label: "Price goes above")
                            alertTypeButton(.below, icon: "arrow.down", label: "Price goes below")
                            alertTypeButton(.percentIncrease, icon: "percent", label: "Increases by %")
                            alertTypeButton(.percentDecrease, icon: "percent", label: "Decreases by %")
                        }
                    }
                    
                    // Target value
                    VStack(alignment: .leading, spacing: HawalaTheme.Spacing.xs) {
                        Text(isPercentAlert ? "PERCENTAGE" : "TARGET PRICE")
                            .font(HawalaTheme.Typography.label)
                            .foregroundColor(HawalaTheme.Colors.textTertiary)
                        
                        HStack {
                            if !isPercentAlert {
                                Text("$")
                                    .font(HawalaTheme.Typography.h4)
                                    .foregroundColor(HawalaTheme.Colors.textSecondary)
                            }
                            
                            TextField(isPercentAlert ? "10" : "50000", text: $targetValue)
                                .textFieldStyle(.plain)
                                .font(HawalaTheme.Typography.h3)
                            
                            if isPercentAlert {
                                Text("%")
                                    .font(HawalaTheme.Typography.h4)
                                    .foregroundColor(HawalaTheme.Colors.textSecondary)
                            }
                        }
                        .padding(HawalaTheme.Spacing.md)
                        .background(HawalaTheme.Colors.backgroundTertiary)
                        .clipShape(RoundedRectangle(cornerRadius: HawalaTheme.Radius.md))
                    }
                    
                    // Note
                    VStack(alignment: .leading, spacing: HawalaTheme.Spacing.xs) {
                        Text("NOTE (OPTIONAL)")
                            .font(HawalaTheme.Typography.label)
                            .foregroundColor(HawalaTheme.Colors.textTertiary)
                        
                        TextField("Reminder for this alert...", text: $alertNote)
                            .textFieldStyle(.plain)
                            .font(HawalaTheme.Typography.body)
                            .padding(HawalaTheme.Spacing.md)
                            .background(HawalaTheme.Colors.backgroundTertiary)
                            .clipShape(RoundedRectangle(cornerRadius: HawalaTheme.Radius.md))
                    }
                    
                    // Repeat toggle
                    Toggle(isOn: $repeatAlert) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Repeat Alert")
                                .font(HawalaTheme.Typography.body)
                                .foregroundColor(HawalaTheme.Colors.textPrimary)
                            
                            Text("Alert will reset after being triggered")
                                .font(HawalaTheme.Typography.caption)
                                .foregroundColor(HawalaTheme.Colors.textSecondary)
                        }
                    }
                    .toggleStyle(SwitchToggleStyle(tint: HawalaTheme.Colors.accent))
                }
                .padding()
            }
        }
        .frame(width: 450, height: 600)
        .background(HawalaTheme.Colors.background)
    }
    
    private var isPercentAlert: Bool {
        alertType == .percentIncrease || alertType == .percentDecrease || alertType == .percentChange
    }
    
    private func alertTypeButton(_ type: HawalaBridge.AlertType, icon: String, label: String) -> some View {
        Button(action: { alertType = type }) {
            HStack {
                Image(systemName: alertType == type ? "checkmark.circle.fill" : "circle")
                    .foregroundColor(alertType == type ? HawalaTheme.Colors.accent : HawalaTheme.Colors.textTertiary)
                
                Image(systemName: icon)
                    .font(.system(size: 14))
                    .foregroundColor(HawalaTheme.Colors.textSecondary)
                
                Text(label)
                    .font(HawalaTheme.Typography.body)
                    .foregroundColor(HawalaTheme.Colors.textPrimary)
                
                Spacer()
            }
            .padding(HawalaTheme.Spacing.md)
            .background(
                alertType == type
                    ? HawalaTheme.Colors.accentSubtle
                    : HawalaTheme.Colors.backgroundSecondary
            )
            .clipShape(RoundedRectangle(cornerRadius: HawalaTheme.Radius.md))
        }
        .buttonStyle(.plain)
    }
    
    // MARK: - Error Toast
    
    private func errorToast(message: String) -> some View {
        HStack(spacing: HawalaTheme.Spacing.sm) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundColor(HawalaTheme.Colors.error)
            
            Text(message)
                .font(HawalaTheme.Typography.bodySmall)
                .foregroundColor(HawalaTheme.Colors.textPrimary)
        }
        .padding(HawalaTheme.Spacing.md)
        .background(HawalaTheme.Colors.error.opacity(0.15))
        .clipShape(RoundedRectangle(cornerRadius: HawalaTheme.Radius.md))
    }
    
    // MARK: - Helpers
    
    private func formatPrice(_ price: Double) -> String {
        if price >= 1000 {
            return String(format: "$%.2f", price)
        } else if price >= 1 {
            return String(format: "$%.4f", price)
        } else {
            return String(format: "$%.6f", price)
        }
    }
    
    private func formatTimestamp(_ timestamp: UInt64) -> String {
        let date = Date(timeIntervalSince1970: TimeInterval(timestamp))
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: date, relativeTo: Date())
    }
    
    // MARK: - Data Operations
    
    private func fetchStats() async {
        isLoading = true
        error = nil
        
        do {
            stats = try HawalaBridge.shared.getAlertStats()
        } catch {
            self.error = error.localizedDescription
        }
        
        isLoading = false
    }
    
    private func fetchPrices() async {
        for symbol in supportedSymbols.prefix(5) {
            do {
                let price = try HawalaBridge.shared.getPrice(symbol: symbol)
                currentPrices[symbol] = price
            } catch {
                // Silently fail for individual prices
            }
        }
    }
    
    private func createAlert() async {
        guard let target = Double(targetValue), target > 0 else {
            error = "Please enter a valid target value"
            return
        }
        
        isLoading = true
        error = nil
        
        do {
            let alert = try HawalaBridge.shared.createPriceAlert(
                symbol: selectedSymbol,
                alertType: alertType,
                targetValue: target,
                note: alertNote.isEmpty ? nil : alertNote,
                repeat: repeatAlert
            )
            
            alerts.insert(alert, at: 0)
            
            // Reset form
            targetValue = ""
            alertNote = ""
            repeatAlert = false
            showCreateSheet = false
            
            // Refresh stats
            await fetchStats()
        } catch {
            self.error = error.localizedDescription
        }
        
        isLoading = false
    }
}

// MARK: - Preview

#if DEBUG
struct PriceAlertsView_Previews: PreviewProvider {
    static var previews: some View {
        PriceAlertsView()
            .preferredColorScheme(.dark)
    }
}
#endif
