import SwiftUI

// MARK: - Portfolio Analytics View

struct PortfolioAnalyticsView: View {
    @StateObject private var viewModel = PortfolioAnalyticsViewModel()
    @State private var selectedTimeRange: TimeRange = .week
    @State private var selectedChartType: ChartType = .line
    
    @Environment(\.colorScheme) private var colorScheme
    
    private var cardBackground: Color {
        colorScheme == .dark ? Color.white.opacity(0.05) : Color.black.opacity(0.03)
    }
    
    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                // Header with total value
                portfolioHeader
                
                // Time range selector
                timeRangeSelector
                
                // Main chart
                portfolioChart
                
                // Asset allocation
                assetAllocationSection
                
                // Performance metrics
                performanceMetrics
                
                // Recent changes
                recentChangesSection
            }
            .padding(24)
        }
        .onAppear {
            viewModel.loadData(for: selectedTimeRange)
        }
        .onChange(of: selectedTimeRange) { newRange in
            viewModel.loadData(for: newRange)
        }
    }
    
    // MARK: - Portfolio Header
    
    private var portfolioHeader: some View {
        VStack(spacing: 12) {
            Text("Portfolio Value")
                .font(.subheadline)
                .foregroundColor(.secondary)
            
            Text(viewModel.totalValue)
                .font(.system(size: 42, weight: .bold, design: .rounded))
                .foregroundColor(.primary)
            
            HStack(spacing: 8) {
                Image(systemName: viewModel.isPositiveChange ? "arrow.up.right" : "arrow.down.right")
                    .font(.caption.bold())
                
                Text(viewModel.changeText)
                    .font(.subheadline.bold())
                
                Text(viewModel.changePercentage)
                    .font(.caption)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(viewModel.isPositiveChange ? Color.green.opacity(0.2) : Color.red.opacity(0.2))
                    .cornerRadius(4)
            }
            .foregroundColor(viewModel.isPositiveChange ? .green : .red)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 32)
        .background(cardBackground)
        .cornerRadius(20)
    }
    
    // MARK: - Time Range Selector
    
    private var timeRangeSelector: some View {
        HStack(spacing: 0) {
            ForEach(TimeRange.allCases, id: \.self) { range in
                Button {
                    withAnimation(.spring(response: 0.3)) {
                        selectedTimeRange = range
                    }
                } label: {
                    Text(range.label)
                        .font(.subheadline.weight(selectedTimeRange == range ? .semibold : .regular))
                        .foregroundColor(selectedTimeRange == range ? .white : .secondary)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .background(
                            selectedTimeRange == range ?
                            Color.blue : Color.clear
                        )
                        .cornerRadius(8)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(4)
        .background(cardBackground)
        .cornerRadius(12)
    }
    
    // MARK: - Portfolio Chart
    
    private var portfolioChart: some View {
        VStack(spacing: 16) {
            // Chart type toggle
            HStack {
                Picker("Chart Type", selection: $selectedChartType) {
                    ForEach(ChartType.allCases, id: \.self) { type in
                        Image(systemName: type.icon).tag(type)
                    }
                }
                .pickerStyle(.segmented)
                .frame(width: 120)
                
                Spacer()
                
                if viewModel.isLoading {
                    ProgressView()
                        .scaleEffect(0.8)
                }
            }
            
            // Chart
            if viewModel.dataPoints.isEmpty {
                emptyChartPlaceholder
            } else {
                chartContent
            }
        }
        .padding(20)
        .background(cardBackground)
        .cornerRadius(16)
    }
    
    private var emptyChartPlaceholder: some View {
        VStack(spacing: 12) {
            Image(systemName: "chart.line.uptrend.xyaxis")
                .font(.system(size: 48))
                .foregroundColor(.secondary.opacity(0.5))
            
            Text("No data available")
                .font(.subheadline)
                .foregroundColor(.secondary)
            
            Text("Historical data will appear once you have transactions")
                .font(.caption)
                .foregroundColor(.secondary.opacity(0.7))
                .multilineTextAlignment(.center)
        }
        .frame(height: 200)
        .frame(maxWidth: .infinity)
    }
    
    private var chartContent: some View {
        GeometryReader { geometry in
            let width = geometry.size.width
            let height: CGFloat = 200
            
            ZStack(alignment: .bottomLeading) {
                // Grid lines
                chartGridLines(width: width, height: height)
                
                // Chart line/area
                if selectedChartType == .line {
                    lineChart(width: width, height: height)
                } else {
                    areaChart(width: width, height: height)
                }
                
                // Value labels on Y axis
                chartYAxisLabels(height: height)
                
                // Date labels on X axis
                chartXAxisLabels(width: width, height: height)
            }
        }
        .frame(height: 220)
    }
    
    private func chartGridLines(width: CGFloat, height: CGFloat) -> some View {
        ZStack {
            // Horizontal grid lines
            ForEach(0..<5) { i in
                let y = height - (height / 4 * CGFloat(i))
                Path { path in
                    path.move(to: CGPoint(x: 40, y: y))
                    path.addLine(to: CGPoint(x: width, y: y))
                }
                .stroke(Color.gray.opacity(0.2), style: StrokeStyle(lineWidth: 1, dash: [5, 5]))
            }
        }
    }
    
    private func lineChart(width: CGFloat, height: CGFloat) -> some View {
        let points = normalizedPoints(width: width - 40, height: height - 20, xOffset: 40)
        
        return ZStack {
            // Gradient under line
            Path { path in
                guard points.count > 1 else { return }
                path.move(to: CGPoint(x: points[0].x, y: height - 20))
                path.addLine(to: points[0])
                for point in points.dropFirst() {
                    path.addLine(to: point)
                }
                path.addLine(to: CGPoint(x: points.last!.x, y: height - 20))
                path.closeSubpath()
            }
            .fill(
                LinearGradient(
                    colors: [Color.blue.opacity(0.3), Color.blue.opacity(0.0)],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
            
            // Main line
            Path { path in
                guard points.count > 1 else { return }
                path.move(to: points[0])
                for point in points.dropFirst() {
                    path.addLine(to: point)
                }
            }
            .stroke(Color.blue, style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
            
            // Data points
            ForEach(Array(points.enumerated()), id: \.offset) { _, point in
                Circle()
                    .fill(Color.blue)
                    .frame(width: 6, height: 6)
                    .position(point)
            }
        }
    }
    
    private func areaChart(width: CGFloat, height: CGFloat) -> some View {
        let points = normalizedPoints(width: width - 40, height: height - 20, xOffset: 40)
        
        return Path { path in
            guard points.count > 1 else { return }
            path.move(to: CGPoint(x: points[0].x, y: height - 20))
            path.addLine(to: points[0])
            for point in points.dropFirst() {
                path.addLine(to: point)
            }
            path.addLine(to: CGPoint(x: points.last!.x, y: height - 20))
            path.closeSubpath()
        }
        .fill(
            LinearGradient(
                colors: [Color.blue.opacity(0.6), Color.purple.opacity(0.3)],
                startPoint: .top,
                endPoint: .bottom
            )
        )
    }
    
    private func normalizedPoints(width: CGFloat, height: CGFloat, xOffset: CGFloat) -> [CGPoint] {
        guard !viewModel.dataPoints.isEmpty else { return [] }
        
        let values = viewModel.dataPoints.map { $0.value }
        let minVal = values.min() ?? 0
        let maxVal = values.max() ?? 1
        let range = maxVal - minVal
        let safeRange = range > 0 ? range : 1
        
        return viewModel.dataPoints.enumerated().map { index, point in
            let x = xOffset + (width / CGFloat(viewModel.dataPoints.count - 1)) * CGFloat(index)
            let normalizedY = (point.value - minVal) / safeRange
            let y = height - (normalizedY * (height - 20)) - 20
            return CGPoint(x: x, y: y)
        }
    }
    
    private func chartYAxisLabels(height: CGFloat) -> some View {
        let values = viewModel.dataPoints.map { $0.value }
        let minVal = values.min() ?? 0
        let maxVal = values.max() ?? 100
        
        return VStack {
            ForEach(0..<5) { i in
                let value = minVal + (maxVal - minVal) / 4 * Double(4 - i)
                Text(formatValue(value))
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundColor(.secondary)
                    .frame(width: 35, alignment: .trailing)
                if i < 4 { Spacer() }
            }
        }
        .frame(height: height - 20)
        .padding(.bottom, 20)
    }
    
    private func chartXAxisLabels(width: CGFloat, height: CGFloat) -> some View {
        HStack {
            ForEach(Array(viewModel.dateLabels.enumerated()), id: \.offset) { index, label in
                if index == 0 || index == viewModel.dateLabels.count - 1 || index == viewModel.dateLabels.count / 2 {
                    Text(label)
                        .font(.system(size: 9))
                        .foregroundColor(.secondary)
                }
                if index < viewModel.dateLabels.count - 1 {
                    Spacer()
                }
            }
        }
        .padding(.leading, 40)
        .offset(y: height / 2 + 5)
    }
    
    private func formatValue(_ value: Double) -> String {
        if value >= 1000000 {
            return String(format: "$%.1fM", value / 1000000)
        } else if value >= 1000 {
            return String(format: "$%.1fK", value / 1000)
        } else {
            return String(format: "$%.0f", value)
        }
    }
    
    // MARK: - Asset Allocation
    
    private var assetAllocationSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Asset Allocation")
                .font(.headline)
            
            HStack(spacing: 20) {
                // Pie chart
                pieChart
                    .frame(width: 120, height: 120)
                
                // Legend
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(viewModel.allocations) { allocation in
                        allocationLegendItem(allocation)
                    }
                }
            }
        }
        .padding(20)
        .background(cardBackground)
        .cornerRadius(16)
    }
    
    private var pieChart: some View {
        GeometryReader { geometry in
            let center = CGPoint(x: geometry.size.width / 2, y: geometry.size.height / 2)
            let radius = min(geometry.size.width, geometry.size.height) / 2
            
            ZStack {
                ForEach(Array(viewModel.allocations.enumerated()), id: \.element.id) { index, allocation in
                    let startAngle = viewModel.startAngle(for: index)
                    let endAngle = viewModel.endAngle(for: index)
                    
                    Path { path in
                        path.move(to: center)
                        path.addArc(center: center, radius: radius,
                                    startAngle: startAngle, endAngle: endAngle,
                                    clockwise: false)
                        path.closeSubpath()
                    }
                    .fill(allocation.color)
                }
                
                // Center hole for donut effect
                Circle()
                    .fill(cardBackground)
                    .frame(width: radius, height: radius)
            }
        }
    }
    
    private func allocationLegendItem(_ allocation: AssetAllocation) -> some View {
        HStack(spacing: 8) {
            Circle()
                .fill(allocation.color)
                .frame(width: 10, height: 10)
            
            Text(allocation.symbol)
                .font(.subheadline)
                .foregroundColor(.primary)
            
            Spacer()
            
            Text(String(format: "%.1f%%", allocation.percentage))
                .font(.subheadline)
                .foregroundColor(.secondary)
        }
    }
    
    // MARK: - Performance Metrics
    
    private var performanceMetrics: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Performance")
                .font(.headline)
            
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                metricCard(title: "24h High", value: viewModel.dayHigh, icon: "arrow.up", color: .green)
                metricCard(title: "24h Low", value: viewModel.dayLow, icon: "arrow.down", color: .red)
                metricCard(title: "All-Time High", value: viewModel.allTimeHigh, icon: "star.fill", color: .yellow)
                metricCard(title: "Best Performer", value: viewModel.bestPerformer, icon: "trophy.fill", color: .orange)
            }
        }
        .padding(20)
        .background(cardBackground)
        .cornerRadius(16)
    }
    
    private func metricCard(title: String, value: String, icon: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.caption)
                    .foregroundColor(color)
                Text(title)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            Text(value)
                .font(.headline)
                .foregroundColor(.primary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(Color.white.opacity(0.03))
        .cornerRadius(10)
    }
    
    // MARK: - Recent Changes
    
    private var recentChangesSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Price Changes")
                .font(.headline)
            
            ForEach(viewModel.priceChanges) { change in
                priceChangeRow(change)
            }
        }
        .padding(20)
        .background(cardBackground)
        .cornerRadius(16)
    }
    
    private func priceChangeRow(_ change: PriceChange) -> some View {
        HStack(spacing: 12) {
            // Asset icon
            ZStack {
                Circle()
                    .fill(change.color.opacity(0.2))
                    .frame(width: 36, height: 36)
                
                Text(change.symbol.prefix(1))
                    .font(.headline)
                    .foregroundColor(change.color)
            }
            
            VStack(alignment: .leading, spacing: 2) {
                Text(change.symbol)
                    .font(.subheadline.bold())
                Text(change.name)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            VStack(alignment: .trailing, spacing: 2) {
                Text(change.currentPrice)
                    .font(.subheadline)
                
                HStack(spacing: 4) {
                    Image(systemName: change.isPositive ? "arrow.up.right" : "arrow.down.right")
                        .font(.system(size: 10))
                    Text(change.changePercent)
                        .font(.caption)
                }
                .foregroundColor(change.isPositive ? .green : .red)
            }
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Supporting Types

enum TimeRange: String, CaseIterable {
    case day = "1D"
    case week = "1W"
    case month = "1M"
    case threeMonths = "3M"
    case year = "1Y"
    case all = "All"
    
    var label: String { rawValue }
}

enum ChartType: String, CaseIterable {
    case line
    case area
    
    var icon: String {
        switch self {
        case .line: return "chart.line.uptrend.xyaxis"
        case .area: return "chart.bar.fill"
        }
    }
}

struct DataPoint: Identifiable {
    let id = UUID()
    let date: Date
    let value: Double
}

struct AssetAllocation: Identifiable {
    let id = UUID()
    let symbol: String
    let percentage: Double
    let color: Color
}

struct PriceChange: Identifiable {
    let id = UUID()
    let symbol: String
    let name: String
    let currentPrice: String
    let changePercent: String
    let isPositive: Bool
    let color: Color
}

// MARK: - View Model

@MainActor
class PortfolioAnalyticsViewModel: ObservableObject {
    @Published var isLoading = false
    @Published var dataPoints: [DataPoint] = []
    @Published var dateLabels: [String] = []
    @Published var allocations: [AssetAllocation] = []
    @Published var priceChanges: [PriceChange] = []
    
    @Published var totalValue = "$0.00"
    @Published var changeText = "+$0.00"
    @Published var changePercentage = "+0.00%"
    @Published var isPositiveChange = true
    
    @Published var dayHigh = "$0.00"
    @Published var dayLow = "$0.00"
    @Published var allTimeHigh = "$0.00"
    @Published var bestPerformer = "BTC"
    
    private let dateFormatter: DateFormatter = {
        let df = DateFormatter()
        df.dateFormat = "MMM d"
        return df
    }()
    
    func loadData(for timeRange: TimeRange) {
        isLoading = true
        
        // Simulate loading - in production, fetch real historical data
        Task {
            try? await Task.sleep(nanoseconds: 500_000_000)
            
            await MainActor.run {
                generateMockData(for: timeRange)
                isLoading = false
            }
        }
    }
    
    private func generateMockData(for timeRange: TimeRange) {
        let points = timeRange == .day ? 24 : (timeRange == .week ? 7 : (timeRange == .month ? 30 : 90))
        let baseValue = 15000.0
        var currentValue = baseValue
        var mockPoints: [DataPoint] = []
        var labels: [String] = []
        
        let calendar = Calendar.current
        let now = Date()
        
        for i in 0..<points {
            let date = calendar.date(byAdding: timeRange == .day ? .hour : .day, value: -points + i + 1, to: now) ?? now
            let randomChange = Double.random(in: -0.03...0.04)
            currentValue *= (1 + randomChange)
            
            mockPoints.append(DataPoint(date: date, value: currentValue))
            
            if timeRange == .day {
                let hourFormatter = DateFormatter()
                hourFormatter.dateFormat = "HH:mm"
                labels.append(hourFormatter.string(from: date))
            } else {
                labels.append(dateFormatter.string(from: date))
            }
        }
        
        dataPoints = mockPoints
        dateLabels = labels
        
        // Update summary values
        let startValue = mockPoints.first?.value ?? baseValue
        let endValue = mockPoints.last?.value ?? baseValue
        let change = endValue - startValue
        let changePercent = (change / startValue) * 100
        
        totalValue = String(format: "$%.2f", endValue)
        changeText = String(format: "%@$%.2f", change >= 0 ? "+" : "", abs(change))
        changePercentage = String(format: "%@%.2f%%", changePercent >= 0 ? "+" : "", changePercent)
        isPositiveChange = change >= 0
        
        // Mock metrics
        dayHigh = String(format: "$%.2f", (mockPoints.map { $0.value }.max() ?? endValue) * 1.02)
        dayLow = String(format: "$%.2f", (mockPoints.map { $0.value }.min() ?? endValue) * 0.98)
        allTimeHigh = String(format: "$%.2f", endValue * 1.15)
        
        // Mock allocations
        allocations = [
            AssetAllocation(symbol: "BTC", percentage: 45.2, color: .orange),
            AssetAllocation(symbol: "ETH", percentage: 28.3, color: .purple),
            AssetAllocation(symbol: "SOL", percentage: 12.5, color: .cyan),
            AssetAllocation(symbol: "XRP", percentage: 8.1, color: .blue),
            AssetAllocation(symbol: "Other", percentage: 5.9, color: .gray)
        ]
        
        // Mock price changes
        priceChanges = [
            PriceChange(symbol: "BTC", name: "Bitcoin", currentPrice: "$98,234.12", changePercent: "+2.34%", isPositive: true, color: .orange),
            PriceChange(symbol: "ETH", name: "Ethereum", currentPrice: "$3,456.78", changePercent: "+1.23%", isPositive: true, color: .purple),
            PriceChange(symbol: "SOL", name: "Solana", currentPrice: "$234.56", changePercent: "-0.87%", isPositive: false, color: .cyan),
            PriceChange(symbol: "XRP", name: "Ripple", currentPrice: "$1.23", changePercent: "+5.67%", isPositive: true, color: .blue),
            PriceChange(symbol: "LTC", name: "Litecoin", currentPrice: "$123.45", changePercent: "-1.23%", isPositive: false, color: .gray)
        ]
    }
    
    func startAngle(for index: Int) -> Angle {
        let total = allocations.prefix(index).reduce(0) { $0 + $1.percentage }
        return Angle(degrees: total * 3.6 - 90)
    }
    
    func endAngle(for index: Int) -> Angle {
        let total = allocations.prefix(index + 1).reduce(0) { $0 + $1.percentage }
        return Angle(degrees: total * 3.6 - 90)
    }
}

// MARK: - Preview

#if DEBUG
struct PortfolioAnalyticsView_Previews: PreviewProvider {
    static var previews: some View {
        PortfolioAnalyticsView()
            .frame(width: 600, height: 800)
            .preferredColorScheme(.dark)
    }
}
#endif
