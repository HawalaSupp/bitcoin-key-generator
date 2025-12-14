import SwiftUI

// MARK: - Fee Intelligence View
// Phase 5.2: Smart Transaction Features - Fee Intelligence UI

struct FeeIntelligenceView: View {
    @StateObject private var manager = FeeIntelligenceManager.shared
    @State private var selectedChain: FeeTrackableChain = .bitcoin
    @State private var selectedTimeRange: TimeRange = .day
    @State private var showingAddAlert = false
    @State private var showingAddPreset = false
    @State private var showingSettings = false
    
    enum TimeRange: String, CaseIterable {
        case hour = "1H"
        case day = "24H"
        case week = "7D"
        
        var hours: Int {
            switch self {
            case .hour: return 1
            case .day: return 24
            case .week: return 168
            }
        }
    }
    
    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                // Header
                headerSection
                
                // Chain Selector
                chainSelectorSection
                
                // Current Fees Card
                currentFeesCard
                
                // Network Status
                networkStatusCard
                
                // Fee Comparison
                feeComparisonCard
                
                // Predictions
                predictionsCard
                
                // Historical Chart
                historicalChartCard
                
                // Custom Presets
                customPresetsSection
                
                // Fee Alerts
                feeAlertsSection
                
                // Savings Summary
                savingsSummaryCard
            }
            .padding()
        }
        .background(Color(NSColor.windowBackgroundColor))
        .navigationTitle("Fee Intelligence")
        .toolbar {
            ToolbarItem(placement: .automatic) {
                Button(action: { showingSettings = true }) {
                    Image(systemName: "gearshape")
                }
            }
            
            ToolbarItem(placement: .automatic) {
                Button(action: {
                    Task {
                        await manager.refreshAllFees()
                    }
                }) {
                    Image(systemName: manager.isLoading ? "arrow.triangle.2.circlepath" : "arrow.clockwise")
                        .rotationEffect(.degrees(manager.isLoading ? 360 : 0))
                        .animation(manager.isLoading ? .linear(duration: 1).repeatForever(autoreverses: false) : .default, value: manager.isLoading)
                }
                .disabled(manager.isLoading)
            }
        }
        .sheet(isPresented: $showingAddAlert) {
            AddFeeAlertSheet(chain: selectedChain)
        }
        .sheet(isPresented: $showingAddPreset) {
            AddCustomPresetSheet(chain: selectedChain)
        }
        .sheet(isPresented: $showingSettings) {
            FeeIntelligenceSettingsSheet()
        }
    }
    
    // MARK: - Header
    
    private var headerSection: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text("Fee Intelligence")
                    .font(.title.bold())
                
                if manager.isLoading {
                    Text("Updating fees...")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                } else if let record = manager.currentFees[selectedChain] {
                    Text("Last updated: \(record.timestamp, style: .relative)")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
            }
            
            Spacer()
            
            // Quick Status Badge
            if let record = manager.currentFees[selectedChain] {
                FeeIntelCongestionBadge(level: record.congestionLevel)
            }
        }
    }
    
    // MARK: - Chain Selector
    
    private var chainSelectorSection: some View {
        HStack(spacing: 12) {
            ForEach(FeeTrackableChain.allCases) { chain in
                FeeIntelChainButton(
                    chain: chain,
                    isSelected: selectedChain == chain,
                    currentFee: manager.currentFees[chain]?.normalFee
                ) {
                    withAnimation {
                        selectedChain = chain
                    }
                }
            }
        }
    }
    
    // MARK: - Current Fees Card
    
    private var currentFeesCard: some View {
        GroupBox {
            VStack(spacing: 16) {
                HStack {
                    Text("Current Fees")
                        .font(.headline)
                    Spacer()
                    Text(selectedChain.feeUnit)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                if let record = manager.currentFees[selectedChain] {
                    HStack(spacing: 20) {
                        FeeIntelPresetCard(
                            preset: .economy,
                            fee: record.economyFee,
                            chain: selectedChain,
                            estimate: manager.getConfirmationEstimate(chain: selectedChain, preset: .economy)
                        )
                        
                        FeeIntelPresetCard(
                            preset: .normal,
                            fee: record.normalFee,
                            chain: selectedChain,
                            estimate: manager.getConfirmationEstimate(chain: selectedChain, preset: .normal)
                        )
                        
                        FeeIntelPresetCard(
                            preset: .priority,
                            fee: record.priorityFee,
                            chain: selectedChain,
                            estimate: manager.getConfirmationEstimate(chain: selectedChain, preset: .priority)
                        )
                    }
                } else {
                    Text("Loading fees...")
                        .foregroundColor(.secondary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 20)
                }
            }
            .padding(.vertical, 8)
        }
    }
    
    // MARK: - Network Status Card
    
    private var networkStatusCard: some View {
        GroupBox {
            VStack(spacing: 12) {
                HStack {
                    Text("Network Status")
                        .font(.headline)
                    Spacer()
                }
                
                if let record = manager.currentFees[selectedChain] {
                    HStack(spacing: 20) {
                        // Congestion Level
                        VStack(spacing: 4) {
                            Image(systemName: record.congestionLevel.icon)
                                .font(.title2)
                                .foregroundColor(colorForLevel(record.congestionLevel))
                            Text(record.congestionLevel.rawValue)
                                .font(.caption.bold())
                            Text("Congestion")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                        .frame(maxWidth: .infinity)
                        
                        Divider()
                            .frame(height: 50)
                        
                        // Good Time to Send?
                        let sendCheck = manager.isGoodTimeToSend(chain: selectedChain)
                        VStack(spacing: 4) {
                            Image(systemName: sendCheck.good ? "checkmark.circle.fill" : "clock.fill")
                                .font(.title2)
                                .foregroundColor(sendCheck.good ? .green : .orange)
                            Text(sendCheck.good ? "Good" : "Wait")
                                .font(.caption.bold())
                            Text("Timing")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                        .frame(maxWidth: .infinity)
                        
                        Divider()
                            .frame(height: 50)
                        
                        // Mempool Size (Bitcoin only)
                        if let mempoolSize = record.mempoolSize {
                            VStack(spacing: 4) {
                                Text("\(formatNumber(mempoolSize))")
                                    .font(.title3.bold())
                                Text("Pending TXs")
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                            }
                            .frame(maxWidth: .infinity)
                        } else if let baseFee = record.baseFee {
                            // Base Fee (Ethereum)
                            VStack(spacing: 4) {
                                Text("\(String(format: "%.1f", baseFee))")
                                    .font(.title3.bold())
                                Text("Base Fee")
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                            }
                            .frame(maxWidth: .infinity)
                        } else {
                            VStack(spacing: 4) {
                                Text("-")
                                    .font(.title3.bold())
                                Text("Extra Info")
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                            }
                            .frame(maxWidth: .infinity)
                        }
                    }
                    
                    // Send Recommendation
                    let sendCheck = manager.isGoodTimeToSend(chain: selectedChain)
                    HStack {
                        Image(systemName: "lightbulb.fill")
                            .foregroundColor(.yellow)
                        Text(sendCheck.reason)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .padding(.top, 8)
                }
            }
            .padding(.vertical, 8)
        }
    }
    
    // MARK: - Fee Comparison Card
    
    private var feeComparisonCard: some View {
        GroupBox {
            VStack(spacing: 12) {
                HStack {
                    Text("Fee Analysis")
                        .font(.headline)
                    Spacer()
                    
                    Picker("Range", selection: $selectedTimeRange) {
                        ForEach(TimeRange.allCases, id: \.self) { range in
                            Text(range.rawValue).tag(range)
                        }
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 150)
                }
                
                let avg = manager.getAverageFee(chain: selectedChain, hours: selectedTimeRange.hours)
                let range = manager.getFeeRange(chain: selectedChain, hours: selectedTimeRange.hours)
                let volatility = manager.getFeeVolatility(chain: selectedChain, hours: selectedTimeRange.hours)
                
                HStack(spacing: 30) {
                    FeeIntelStatBox(title: "Average", value: String(format: "%.1f", avg), unit: selectedChain.feeUnit)
                    FeeIntelStatBox(title: "Min", value: String(format: "%.1f", range.min), unit: selectedChain.feeUnit)
                    FeeIntelStatBox(title: "Max", value: String(format: "%.1f", range.max), unit: selectedChain.feeUnit)
                    FeeIntelStatBox(title: "Volatility", value: String(format: "%.1f", volatility), unit: "σ")
                }
                
                if let current = manager.currentFees[selectedChain]?.normalFee, avg > 0 {
                    let diff = ((current - avg) / avg) * 100
                    let isLower = diff < 0
                    
                    HStack {
                        Image(systemName: isLower ? "arrow.down.circle.fill" : "arrow.up.circle.fill")
                            .foregroundColor(isLower ? .green : .red)
                        Text("Current fee is \(String(format: "%.0f%%", abs(diff))) \(isLower ? "below" : "above") \(selectedTimeRange.rawValue) average")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            }
            .padding(.vertical, 8)
        }
    }
    
    // MARK: - Predictions Card
    
    private var predictionsCard: some View {
        GroupBox {
            VStack(spacing: 12) {
                HStack {
                    Text("Optimal Send Time")
                        .font(.headline)
                    Spacer()
                }
                
                if let prediction = manager.getOptimalSendTime(for: selectedChain) {
                    VStack(spacing: 8) {
                        HStack {
                            Image(systemName: "clock.badge.checkmark.fill")
                                .font(.title)
                                .foregroundColor(.green)
                            
                            VStack(alignment: .leading) {
                                Text(formatHourNice(prediction.optimalHour))
                                    .font(.title2.bold())
                                Text("Expected fee: \(String(format: "%.1f", prediction.expectedFee)) \(selectedChain.feeUnit)")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            
                            Spacer()
                            
                            // Confidence indicator
                            VStack {
                                Text("\(Int(prediction.confidence * 100))%")
                                    .font(.title3.bold())
                                    .foregroundColor(confidenceColor(prediction.confidence))
                                Text("Confidence")
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                            }
                        }
                        
                        Text(prediction.recommendation)
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                } else {
                    VStack(spacing: 8) {
                        Image(systemName: "chart.line.uptrend.xyaxis")
                            .font(.title)
                            .foregroundColor(.secondary)
                        Text("Collecting data for predictions...")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                }
            }
            .padding(.vertical, 8)
        }
    }
    
    // MARK: - Historical Chart Card
    
    private var historicalChartCard: some View {
        GroupBox {
            VStack(spacing: 12) {
                HStack {
                    Text("Fee History")
                        .font(.headline)
                    Spacer()
                }
                
                let history = manager.getHistory(chain: selectedChain, hours: selectedTimeRange.hours)
                
                if history.isEmpty {
                    VStack(spacing: 8) {
                        Image(systemName: "chart.bar.xaxis")
                            .font(.title)
                            .foregroundColor(.secondary)
                        Text("No historical data yet")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 20)
                } else {
                    // Simple bar chart visualization
                    FeeIntelHistoryChart(records: history, chain: selectedChain)
                        .frame(height: 120)
                }
            }
            .padding(.vertical, 8)
        }
    }
    
    // MARK: - Custom Presets Section
    
    private var customPresetsSection: some View {
        GroupBox {
            VStack(spacing: 12) {
                HStack {
                    Text("Custom Fee Presets")
                        .font(.headline)
                    Spacer()
                    Button(action: { showingAddPreset = true }) {
                        Image(systemName: "plus.circle.fill")
                    }
                }
                
                let presets = manager.getCustomPresets(for: selectedChain)
                
                if presets.isEmpty {
                    VStack(spacing: 8) {
                        Image(systemName: "slider.horizontal.3")
                            .font(.title)
                            .foregroundColor(.secondary)
                        Text("No custom presets for \(selectedChain.rawValue)")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Button("Add Preset") {
                            showingAddPreset = true
                        }
                        .buttonStyle(.bordered)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                } else {
                    ForEach(presets) { preset in
                        FeeIntelPresetRow(preset: preset) {
                            manager.deleteCustomPreset(preset)
                        }
                    }
                }
            }
            .padding(.vertical, 8)
        }
    }
    
    // MARK: - Fee Alerts Section
    
    private var feeAlertsSection: some View {
        GroupBox {
            VStack(spacing: 12) {
                HStack {
                    Text("Fee Alerts")
                        .font(.headline)
                    Spacer()
                    Button(action: { showingAddAlert = true }) {
                        Image(systemName: "plus.circle.fill")
                    }
                }
                
                let alerts = manager.feeAlerts.filter { $0.chain == selectedChain }
                
                if alerts.isEmpty {
                    VStack(spacing: 8) {
                        Image(systemName: "bell.badge")
                            .font(.title)
                            .foregroundColor(.secondary)
                        Text("No alerts for \(selectedChain.rawValue)")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Button("Add Alert") {
                            showingAddAlert = true
                        }
                        .buttonStyle(.bordered)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                } else {
                    ForEach(alerts) { alert in
                        FeeIntelAlertRow(alert: alert) {
                            manager.toggleAlert(alert)
                        } onDelete: {
                            manager.deleteAlert(alert)
                        }
                    }
                }
            }
            .padding(.vertical, 8)
        }
    }
    
    // MARK: - Savings Summary Card
    
    private var savingsSummaryCard: some View {
        GroupBox {
            VStack(spacing: 12) {
                HStack {
                    Text("Fee Savings")
                        .font(.headline)
                    Spacer()
                }
                
                HStack(spacing: 30) {
                    VStack(spacing: 4) {
                        Text("\(manager.savingsHistory.count)")
                            .font(.title.bold())
                        Text("Transactions")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    
                    Divider()
                        .frame(height: 40)
                    
                    VStack(spacing: 4) {
                        let savings = manager.savingsHistory.filter { $0.savedAmount > 0 }
                        Text("\(savings.count)")
                            .font(.title.bold())
                            .foregroundColor(.green)
                        Text("Saved Fees")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    
                    Divider()
                        .frame(height: 40)
                    
                    VStack(spacing: 4) {
                        let totalSaved = manager.savingsHistory.reduce(0) { $0 + max(0, $1.savedAmount) }
                        Text(String(format: "%.2f", totalSaved))
                            .font(.title.bold())
                            .foregroundColor(.green)
                        Text("Total Saved")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            }
            .padding(.vertical, 8)
        }
    }
    
    // MARK: - Helpers
    
    private func colorForLevel(_ level: CongestionLevel) -> Color {
        switch level {
        case .low: return .green
        case .moderate: return .blue
        case .high: return .orange
        case .extreme: return .red
        }
    }
    
    private func formatNumber(_ num: Int) -> String {
        if num >= 1_000_000 {
            return String(format: "%.1fM", Double(num) / 1_000_000)
        } else if num >= 1_000 {
            return String(format: "%.1fK", Double(num) / 1_000)
        }
        return "\(num)"
    }
    
    private func formatHourNice(_ hour: Int) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "h:00 a"
        let date = Calendar.current.date(bySettingHour: hour, minute: 0, second: 0, of: Date()) ?? Date()
        return formatter.string(from: date)
    }
    
    private func confidenceColor(_ confidence: Double) -> Color {
        if confidence >= 0.7 {
            return .green
        } else if confidence >= 0.4 {
            return .orange
        } else {
            return .red
        }
    }
}

// MARK: - Supporting Views

struct FeeIntelCongestionBadge: View {
    let level: CongestionLevel
    
    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: level.icon)
            Text(level.rawValue)
                .font(.caption.bold())
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(colorForLevel.opacity(0.2))
        .foregroundColor(colorForLevel)
        .cornerRadius(8)
    }
    
    private var colorForLevel: Color {
        switch level {
        case .low: return .green
        case .moderate: return .blue
        case .high: return .orange
        case .extreme: return .red
        }
    }
}

struct FeeIntelChainButton: View {
    let chain: FeeTrackableChain
    let isSelected: Bool
    let currentFee: Double?
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Image(systemName: chain.icon)
                    .font(.title2)
                Text(chain.symbol)
                    .font(.caption.bold())
                if let fee = currentFee {
                    Text("\(String(format: "%.0f", fee))")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background(isSelected ? Color.accentColor.opacity(0.2) : Color.secondary.opacity(0.1))
            .cornerRadius(12)
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(isSelected ? Color.accentColor : Color.clear, lineWidth: 2)
            )
        }
        .buttonStyle(.plain)
    }
}

struct FeeIntelPresetCard: View {
    let preset: FeePreset
    let fee: Double
    let chain: FeeTrackableChain
    let estimate: String
    
    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: preset.icon)
                .font(.title2)
                .foregroundColor(colorForPreset)
            
            Text(preset.rawValue)
                .font(.caption.bold())
            
            Text(String(format: "%.1f", fee))
                .font(.title2.bold())
            
            Text(estimate)
                .font(.caption2)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .background(colorForPreset.opacity(0.1))
        .cornerRadius(12)
    }
    
    private var colorForPreset: Color {
        switch preset {
        case .economy: return .green
        case .normal: return .blue
        case .priority: return .orange
        case .custom: return .purple
        }
    }
}

struct FeeIntelStatBox: View {
    let title: String
    let value: String
    let unit: String
    
    var body: some View {
        VStack(spacing: 4) {
            Text(value)
                .font(.title2.bold())
            HStack(spacing: 2) {
                Text(title)
                Text("(\(unit))")
            }
            .font(.caption2)
            .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
    }
}

struct FeeIntelHistoryChart: View {
    let records: [FeeRecord]
    let chain: FeeTrackableChain
    
    var body: some View {
        GeometryReader { geometry in
            let maxFee = records.map { $0.normalFee }.max() ?? 1
            let barWidth = max(4, (geometry.size.width - CGFloat(records.count - 1) * 2) / CGFloat(records.count))
            
            HStack(alignment: .bottom, spacing: 2) {
                ForEach(Array(records.enumerated()), id: \.element.id) { index, record in
                    let height = (record.normalFee / maxFee) * geometry.size.height * 0.9
                    
                    Rectangle()
                        .fill(colorForCongestion(record.congestionLevel))
                        .frame(width: barWidth, height: max(4, height))
                        .cornerRadius(2)
                }
            }
        }
    }
    
    private func colorForCongestion(_ level: CongestionLevel) -> Color {
        switch level {
        case .low: return .green
        case .moderate: return .blue
        case .high: return .orange
        case .extreme: return .red
        }
    }
}

struct FeeIntelPresetRow: View {
    let preset: CustomFeePreset
    let onDelete: () -> Void
    
    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(preset.name)
                    .font(.subheadline.bold())
                Text("\(String(format: "%.1f", preset.feeRate)) \(preset.chain.feeUnit)")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            if preset.isDefault {
                Text("Default")
                    .font(.caption2)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.blue.opacity(0.2))
                    .cornerRadius(4)
            }
            
            Button(action: onDelete) {
                Image(systemName: "trash")
                    .foregroundColor(.red)
            }
            .buttonStyle(.plain)
        }
        .padding(.vertical, 4)
    }
}

struct FeeIntelAlertRow: View {
    let alert: FeeAlert
    let onToggle: () -> Void
    let onDelete: () -> Void
    
    var body: some View {
        HStack {
            Image(systemName: alert.isEnabled ? "bell.fill" : "bell.slash")
                .foregroundColor(alert.isEnabled ? .blue : .secondary)
            
            VStack(alignment: .leading, spacing: 2) {
                Text("Alert when \(alert.isBelow ? "below" : "above") \(String(format: "%.1f", alert.targetFee)) \(alert.chain.feeUnit)")
                    .font(.subheadline)
                
                if let triggered = alert.lastTriggered {
                    Text("Last triggered: \(triggered, style: .relative) ago")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }
            
            Spacer()
            
            Toggle("", isOn: Binding(
                get: { alert.isEnabled },
                set: { _ in onToggle() }
            ))
            .labelsHidden()
            
            Button(action: onDelete) {
                Image(systemName: "trash")
                    .foregroundColor(.red)
            }
            .buttonStyle(.plain)
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Add Alert Sheet

struct AddFeeAlertSheet: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var manager = FeeIntelligenceManager.shared
    
    let chain: FeeTrackableChain
    @State private var targetFee: Double = 10
    @State private var isBelow: Bool = true
    
    var body: some View {
        VStack(spacing: 20) {
            Text("Add Fee Alert")
                .font(.title2.bold())
            
            VStack(alignment: .leading, spacing: 8) {
                Text("Alert when \(chain.rawValue) fees are:")
                    .font(.subheadline)
                
                Picker("Condition", selection: $isBelow) {
                    Text("Below").tag(true)
                    Text("Above").tag(false)
                }
                .pickerStyle(.segmented)
                
                HStack {
                    TextField("Fee", value: $targetFee, format: .number)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 100)
                    
                    Text(chain.feeUnit)
                        .foregroundColor(.secondary)
                }
            }
            .padding()
            .background(Color.secondary.opacity(0.1))
            .cornerRadius(12)
            
            HStack {
                Button("Cancel") {
                    dismiss()
                }
                .keyboardShortcut(.escape)
                
                Spacer()
                
                Button("Add Alert") {
                    let alert = FeeAlert(chain: chain, targetFee: targetFee, isBelow: isBelow)
                    manager.addAlert(alert)
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.return)
            }
        }
        .padding()
        .frame(width: 350)
    }
}

// MARK: - Add Custom Preset Sheet

struct AddCustomPresetSheet: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var manager = FeeIntelligenceManager.shared
    
    let chain: FeeTrackableChain
    @State private var name: String = ""
    @State private var feeRate: Double = 10
    @State private var description: String = ""
    @State private var isDefault: Bool = false
    
    var body: some View {
        VStack(spacing: 20) {
            Text("Add Custom Preset")
                .font(.title2.bold())
            
            VStack(alignment: .leading, spacing: 12) {
                TextField("Preset Name", text: $name)
                    .textFieldStyle(.roundedBorder)
                
                HStack {
                    Text("Fee Rate:")
                    TextField("Rate", value: $feeRate, format: .number)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 80)
                    Text(chain.feeUnit)
                        .foregroundColor(.secondary)
                }
                
                TextField("Description (optional)", text: $description)
                    .textFieldStyle(.roundedBorder)
                
                Toggle("Set as default for \(chain.rawValue)", isOn: $isDefault)
            }
            .padding()
            .background(Color.secondary.opacity(0.1))
            .cornerRadius(12)
            
            HStack {
                Button("Cancel") {
                    dismiss()
                }
                .keyboardShortcut(.escape)
                
                Spacer()
                
                Button("Add Preset") {
                    let preset = CustomFeePreset(
                        name: name,
                        chain: chain,
                        feeRate: feeRate,
                        description: description,
                        isDefault: isDefault
                    )
                    manager.addCustomPreset(preset)
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.return)
                .disabled(name.isEmpty)
            }
        }
        .padding()
        .frame(width: 400)
    }
}

// MARK: - Settings Sheet

struct FeeIntelligenceSettingsSheet: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var manager = FeeIntelligenceManager.shared
    
    var body: some View {
        VStack(spacing: 20) {
            Text("Fee Intelligence Settings")
                .font(.title2.bold())
            
            VStack(alignment: .leading, spacing: 16) {
                Toggle("Auto-refresh fees", isOn: $manager.autoRefreshEnabled)
                    .onChange(of: manager.autoRefreshEnabled) { newValue in
                        manager.setAutoRefresh(enabled: newValue)
                    }
                
                if manager.autoRefreshEnabled {
                    HStack {
                        Text("Refresh interval:")
                        Picker("", selection: $manager.refreshInterval) {
                            Text("30 sec").tag(TimeInterval(30))
                            Text("1 min").tag(TimeInterval(60))
                            Text("5 min").tag(TimeInterval(300))
                            Text("15 min").tag(TimeInterval(900))
                        }
                        .frame(width: 100)
                        .onChange(of: manager.refreshInterval) { newValue in
                            manager.setRefreshInterval(newValue)
                        }
                    }
                }
                
                Divider()
                
                Toggle("Enable fee alerts", isOn: $manager.alertsEnabled)
                
                Toggle("Show fiat equivalent", isOn: $manager.showFiatEquivalent)
            }
            .padding()
            .background(Color.secondary.opacity(0.1))
            .cornerRadius(12)
            
            HStack {
                Spacer()
                Button("Done") {
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.return)
            }
        }
        .padding()
        .frame(width: 400)
    }
}

// MARK: - Preview

#Preview {
    FeeIntelligenceView()
        .frame(width: 700, height: 900)
}
