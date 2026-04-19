import SwiftUI
import Charts

/// Price chart view with time range selector and touch interaction
struct PriceChartView: View {
    let tokenId: String
    let tokenSymbol: String
    let tokenName: String
    
    @StateObject private var chartService = ChartDataService.shared
    @State private var selectedRange: ChartDataService.TimeRange = .day7
    @State private var selectedPrice: Double?
    @State private var selectedDate: Date?
    @State private var showVolume = false
    
    var body: some View {
        VStack(spacing: 16) {
            // Header with price
            priceHeader
            
            // Chart
            chartSection
            
            // Time range selector
            rangeSelector
            
            // Stats
            if let data = chartService.chartData {
                statsSection(data: data)
            }
            
            // Token info
            if let info = chartService.tokenInfo {
                tokenInfoSection(info: info)
            }
        }
        .padding()
        .background(Color(nsColor: .windowBackgroundColor))
        .task {
            await loadData()
        }
        .onChange(of: selectedRange) { _ in
            Task { await loadData() }
        }
    }
    
    // MARK: - Components
    
    private var priceHeader: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(tokenName)
                    .font(.headline)
                Text("(\(tokenSymbol.uppercased()))")
                    .foregroundColor(.secondary)
                Spacer()
            }
            
            HStack(alignment: .firstTextBaseline) {
                if let price = selectedPrice ?? chartService.chartData?.currentPrice {
                    Text(ChartDataService.formatPrice(price))
                        .font(.system(size: 32, weight: .bold, design: .rounded))
                }
                
                if let change = chartService.chartData?.priceChangePercent {
                    HStack(spacing: 2) {
                        Image(systemName: change >= 0 ? "arrow.up.right" : "arrow.down.right")
                        Text(ChartDataService.formatChange(change))
                    }
                    .font(.subheadline)
                    .foregroundColor(change >= 0 ? .green : .red)
                }
                
                Spacer()
            }
            
            if let date = selectedDate {
                Text(date, style: .date)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
    }
    
    private var chartSection: some View {
        Group {
            if chartService.isLoading {
                ProgressView()
                    .frame(height: 200)
            } else if let error = chartService.error {
                VStack {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.largeTitle)
                        .foregroundColor(.orange)
                    Text(error)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .frame(height: 200)
            } else if let data = chartService.chartData, !data.prices.isEmpty {
                priceChart(data: data)
            } else {
                Text("No data available")
                    .foregroundColor(.secondary)
                    .frame(height: 200)
            }
        }
    }
    
    private func priceChart(data: ChartDataService.ChartData) -> some View {
        let isUp = data.isPriceUp
        let color: Color = isUp ? .green : .red
        
        return Chart {
            ForEach(data.prices) { point in
                LineMark(
                    x: .value("Time", point.timestamp),
                    y: .value("Price", point.price)
                )
                .foregroundStyle(color.gradient)
                .interpolationMethod(.catmullRom)
            }
            
            // Area under line
            ForEach(data.prices) { point in
                AreaMark(
                    x: .value("Time", point.timestamp),
                    yStart: .value("Min", data.lowPrice ?? 0),
                    yEnd: .value("Price", point.price)
                )
                .foregroundStyle(
                    LinearGradient(
                        colors: [color.opacity(0.3), color.opacity(0.05)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .interpolationMethod(.catmullRom)
            }
        }
        .chartYScale(domain: (data.lowPrice ?? 0) * 0.99 ... (data.highPrice ?? 100) * 1.01)
        .chartXAxis {
            AxisMarks(values: .automatic(desiredCount: 5)) { _ in
                AxisGridLine()
                AxisValueLabel()
            }
        }
        .chartYAxis {
            AxisMarks(position: .trailing, values: .automatic(desiredCount: 4)) { value in
                AxisGridLine()
                AxisValueLabel {
                    if let price = value.as(Double.self) {
                        Text(ChartDataService.formatPrice(price))
                            .font(.caption2)
                    }
                }
            }
        }
        .frame(height: 220)
        .chartOverlay { proxy in
            GeometryReader { geometry in
                Rectangle()
                    .fill(Color.clear)
                    .contentShape(Rectangle())
                    .gesture(
                        DragGesture(minimumDistance: 0)
                            .onChanged { value in
                                let x = value.location.x
                                if let date: Date = proxy.value(atX: x) {
                                    selectedDate = date
                                    // Find nearest price point
                                    if let nearest = data.prices.min(by: {
                                        abs($0.timestamp.timeIntervalSince(date)) <
                                        abs($1.timestamp.timeIntervalSince(date))
                                    }) {
                                        selectedPrice = nearest.price
                                    }
                                }
                            }
                            .onEnded { _ in
                                selectedPrice = nil
                                selectedDate = nil
                            }
                    )
            }
        }
    }
    
    private var rangeSelector: some View {
        HStack(spacing: 0) {
            ForEach(ChartDataService.TimeRange.allCases, id: \.self) { range in
                Button(action: { selectedRange = range }) {
                    Text(range.rawValue)
                        .font(.caption)
                        .fontWeight(selectedRange == range ? .semibold : .regular)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(
                            selectedRange == range ?
                            Color.accentColor.opacity(0.2) :
                            Color.clear
                        )
                        .cornerRadius(8)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(4)
        .background(Color(nsColor: .controlBackgroundColor))
        .cornerRadius(12)
    }
    
    private func statsSection(data: ChartDataService.ChartData) -> some View {
        HStack(spacing: 20) {
            statItem(title: "High", value: ChartDataService.formatPrice(data.highPrice ?? 0))
            statItem(title: "Low", value: ChartDataService.formatPrice(data.lowPrice ?? 0))
            if let change = data.priceChange {
                statItem(
                    title: "Change",
                    value: ChartDataService.formatPrice(abs(change)),
                    isPositive: change >= 0
                )
            }
        }
        .padding()
        .background(Color(nsColor: .controlBackgroundColor))
        .cornerRadius(12)
    }
    
    private func statItem(title: String, value: String, isPositive: Bool? = nil) -> some View {
        VStack(alignment: .center, spacing: 4) {
            Text(title)
                .font(.caption)
                .foregroundColor(.secondary)
            Text(value)
                .font(.subheadline)
                .fontWeight(.medium)
                .foregroundColor(isPositive.map { $0 ? .green : .red } ?? .primary)
        }
        .frame(maxWidth: .infinity)
    }
    
    private func tokenInfoSection(info: ChartDataService.TokenInfo) -> some View {
        VStack(spacing: 12) {
            HStack {
                Text("Market Stats")
                    .font(.subheadline)
                    .fontWeight(.medium)
                Spacer()
            }
            
            LazyVGrid(columns: [
                GridItem(.flexible()),
                GridItem(.flexible()),
            ], spacing: 12) {
                infoRow(title: "Market Cap", value: ChartDataService.formatLargeNumber(info.marketCap))
                infoRow(title: "24h Volume", value: ChartDataService.formatLargeNumber(info.totalVolume))
                infoRow(title: "24h High", value: ChartDataService.formatPrice(info.high24h))
                infoRow(title: "24h Low", value: ChartDataService.formatPrice(info.low24h))
                infoRow(title: "ATH", value: ChartDataService.formatPrice(info.ath))
                infoRow(title: "ATL", value: ChartDataService.formatPrice(info.atl))
            }
        }
        .padding()
        .background(Color(nsColor: .controlBackgroundColor))
        .cornerRadius(12)
    }
    
    private func infoRow(title: String, value: String) -> some View {
        HStack {
            Text(title)
                .font(.caption)
                .foregroundColor(.secondary)
            Spacer()
            Text(value)
                .font(.caption)
                .fontWeight(.medium)
        }
    }
    
    // MARK: - Actions
    
    private func loadData() async {
        await chartService.fetchChartData(tokenId: tokenId, range: selectedRange)
        await chartService.fetchTokenInfo(tokenId: tokenId)
    }
}

// MARK: - Preview

#if false // Disabled #Preview for command-line builds
#if false
#if false
#Preview {
    PriceChartView(
        tokenId: "bitcoin",
        tokenSymbol: "BTC",
        tokenName: "Bitcoin"
    )
    .frame(width: 400, height: 600)
}
#endif
#endif
#endif
