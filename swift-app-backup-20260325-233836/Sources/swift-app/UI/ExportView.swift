import SwiftUI

// MARK: - Export View

struct ExportView: View {
    @StateObject private var exportService = ExportService.shared
    @State private var selectedFormat: ExportService.ExportFormat = .csv
    @State private var exportType: ExportType = .transactions
    @State private var dateRange: DateRange = .all
    @State private var includeFields: Set<ExportField> = Set(ExportField.allCases)
    @State private var isExporting = false
    @State private var showSuccess = false
    @State private var exportedURL: URL?
    
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dismiss) private var dismiss
    
    enum ExportType: String, CaseIterable {
        case transactions = "Transactions"
        case portfolio = "Portfolio"
        case both = "Full Export"
        
        var icon: String {
            switch self {
            case .transactions: return "list.bullet.rectangle"
            case .portfolio: return "chart.pie"
            case .both: return "square.stack.3d.up"
            }
        }
    }
    
    enum DateRange: String, CaseIterable {
        case week = "Last 7 days"
        case month = "Last 30 days"
        case quarter = "Last 90 days"
        case year = "Last year"
        case all = "All time"
        
        var days: Int? {
            switch self {
            case .week: return 7
            case .month: return 30
            case .quarter: return 90
            case .year: return 365
            case .all: return nil
            }
        }
    }
    
    enum ExportField: String, CaseIterable {
        case date = "Date"
        case type = "Type"
        case amount = "Amount"
        case value = "Value (USD)"
        case fee = "Fee"
        case txHash = "TX Hash"
        case addresses = "Addresses"
        case status = "Status"
        case network = "Network"
    }
    
    private var cardBackground: Color {
        colorScheme == .dark ? Color.white.opacity(0.05) : Color.black.opacity(0.03)
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            header
            
            Divider()
            
            ScrollView {
                VStack(spacing: 24) {
                    // Export type selection
                    exportTypeSection
                    
                    // Format selection
                    formatSection
                    
                    // Date range (for transactions)
                    if exportType != .portfolio {
                        dateRangeSection
                    }
                    
                    // Field selection (for CSV)
                    if selectedFormat == .csv && exportType != .portfolio {
                        fieldSelectionSection
                    }
                    
                    // Preview
                    previewSection
                }
                .padding(24)
            }
            
            Divider()
            
            // Action buttons
            actionButtons
        }
        .frame(width: 500, height: 600)
        .background(Color(nsColor: .windowBackgroundColor))
        .overlay {
            if showSuccess {
                successOverlay
            }
        }
    }
    
    // MARK: - Header
    
    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text("Export Data")
                    .font(.title2.bold())
                
                Text("Download your wallet data for records or tax purposes")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.title2)
                    .foregroundColor(.secondary)
            }
            .buttonStyle(.plain)
        }
        .padding(20)
    }
    
    // MARK: - Export Type Section
    
    private var exportTypeSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("What to Export")
                .font(.subheadline.bold())
            
            HStack(spacing: 12) {
                ForEach(ExportType.allCases, id: \.self) { type in
                    exportTypeButton(type)
                }
            }
        }
    }
    
    private func exportTypeButton(_ type: ExportType) -> some View {
        Button {
            withAnimation(.spring(response: 0.3)) {
                exportType = type
            }
        } label: {
            VStack(spacing: 8) {
                Image(systemName: type.icon)
                    .font(.title2)
                Text(type.rawValue)
                    .font(.caption)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .background(exportType == type ? Color.blue.opacity(0.2) : cardBackground)
            .foregroundColor(exportType == type ? .blue : .secondary)
            .cornerRadius(12)
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(exportType == type ? Color.blue : Color.clear, lineWidth: 2)
            )
        }
        .buttonStyle(.plain)
    }
    
    // MARK: - Format Section
    
    private var formatSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Export Format")
                .font(.subheadline.bold())
            
            HStack(spacing: 12) {
                ForEach(ExportService.ExportFormat.allCases, id: \.self) { format in
                    formatButton(format)
                }
            }
        }
    }
    
    private func formatButton(_ format: ExportService.ExportFormat) -> some View {
        Button {
            withAnimation(.spring(response: 0.3)) {
                selectedFormat = format
            }
        } label: {
            HStack(spacing: 8) {
                Image(systemName: format.icon)
                    .font(.body)
                Text(format.rawValue)
                    .font(.subheadline)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background(selectedFormat == format ? Color.green.opacity(0.2) : cardBackground)
            .foregroundColor(selectedFormat == format ? .green : .secondary)
            .cornerRadius(10)
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(selectedFormat == format ? Color.green : Color.clear, lineWidth: 2)
            )
        }
        .buttonStyle(.plain)
    }
    
    // MARK: - Date Range Section
    
    private var dateRangeSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Date Range")
                .font(.subheadline.bold())
            
            Picker("Date Range", selection: $dateRange) {
                ForEach(DateRange.allCases, id: \.self) { range in
                    Text(range.rawValue).tag(range)
                }
            }
            .pickerStyle(.segmented)
        }
    }
    
    // MARK: - Field Selection Section
    
    private var fieldSelectionSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Include Fields")
                    .font(.subheadline.bold())
                
                Spacer()
                
                Button("Select All") {
                    includeFields = Set(ExportField.allCases)
                }
                .font(.caption)
                .buttonStyle(.plain)
                .foregroundColor(.blue)
            }
            
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                ForEach(ExportField.allCases, id: \.self) { field in
                    fieldToggle(field)
                }
            }
        }
    }
    
    private func fieldToggle(_ field: ExportField) -> some View {
        Button {
            if includeFields.contains(field) {
                includeFields.remove(field)
            } else {
                includeFields.insert(field)
            }
        } label: {
            HStack(spacing: 8) {
                Image(systemName: includeFields.contains(field) ? "checkmark.square.fill" : "square")
                    .foregroundColor(includeFields.contains(field) ? .blue : .secondary)
                
                Text(field.rawValue)
                    .font(.caption)
                    .foregroundColor(.primary)
                
                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(cardBackground)
            .cornerRadius(8)
        }
        .buttonStyle(.plain)
    }
    
    // MARK: - Preview Section
    
    private var previewSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Export Preview")
                .font(.subheadline.bold())
            
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Image(systemName: "doc.fill")
                        .foregroundColor(.secondary)
                    Text(previewFilename)
                        .font(.system(.caption, design: .monospaced))
                        .foregroundColor(.primary)
                }
                
                HStack {
                    Image(systemName: "calendar")
                        .foregroundColor(.secondary)
                    Text(dateRange.rawValue)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                HStack {
                    Image(systemName: "number")
                        .foregroundColor(.secondary)
                    Text("~\(estimatedRecords) records")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(cardBackground)
            .cornerRadius(12)
        }
    }
    
    private var previewFilename: String {
        let date = DateFormatter()
        date.dateFormat = "yyyy-MM-dd"
        let dateStr = date.string(from: Date())
        
        switch exportType {
        case .transactions:
            return "hawala_transactions_\(dateStr).\(selectedFormat.fileExtension)"
        case .portfolio:
            return "hawala_portfolio_\(dateStr).\(selectedFormat.fileExtension)"
        case .both:
            return "hawala_export_\(dateStr).\(selectedFormat.fileExtension)"
        }
    }
    
    private var estimatedRecords: Int {
        // Mock estimate - in production, query actual data
        switch dateRange {
        case .week: return 15
        case .month: return 45
        case .quarter: return 120
        case .year: return 400
        case .all: return 850
        }
    }
    
    // MARK: - Action Buttons
    
    private var actionButtons: some View {
        HStack(spacing: 16) {
            Button("Cancel") {
                dismiss()
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 24)
            .padding(.vertical, 12)
            .background(Color.gray.opacity(0.2))
            .cornerRadius(10)
            
            Spacer()
            
            Button {
                performExport()
            } label: {
                HStack(spacing: 8) {
                    if isExporting {
                        ProgressView()
                            .scaleEffect(0.8)
                            .progressViewStyle(CircularProgressViewStyle(tint: .white))
                    } else {
                        Image(systemName: "square.and.arrow.down")
                    }
                    Text(isExporting ? "Exporting..." : "Export")
                }
                .padding(.horizontal, 24)
                .padding(.vertical, 12)
                .background(Color.blue)
                .foregroundColor(.white)
                .cornerRadius(10)
            }
            .buttonStyle(.plain)
            .disabled(isExporting)
        }
        .padding(20)
    }
    
    // MARK: - Success Overlay
    
    private var successOverlay: some View {
        ZStack {
            Color.black.opacity(0.5)
                .ignoresSafeArea()
            
            VStack(spacing: 20) {
                ZStack {
                    Circle()
                        .fill(Color.green.opacity(0.2))
                        .frame(width: 80, height: 80)
                    
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 50))
                        .foregroundColor(.green)
                }
                
                Text("Export Complete!")
                    .font(.title2.bold())
                
                if let url = exportedURL {
                    Text(url.lastPathComponent)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                HStack(spacing: 16) {
                    Button("Show in Finder") {
                        if let url = exportedURL {
                            NSWorkspace.shared.selectFile(url.path, inFileViewerRootedAtPath: url.deletingLastPathComponent().path)
                        }
                        showSuccess = false
                    }
                    .buttonStyle(.plain)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 10)
                    .background(Color.blue)
                    .foregroundColor(.white)
                    .cornerRadius(8)
                    
                    Button("Done") {
                        showSuccess = false
                        dismiss()
                    }
                    .buttonStyle(.plain)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 10)
                    .background(Color.gray.opacity(0.2))
                    .cornerRadius(8)
                }
            }
            .padding(32)
            .background(
                RoundedRectangle(cornerRadius: 20)
                    .fill(Color(nsColor: .windowBackgroundColor))
            )
        }
    }
    
    // MARK: - Export Logic
    
    private func performExport() {
        isExporting = true
        
        Task {
            do {
                // Generate mock data for demo
                let transactions = generateMockTransactions()
                let portfolio = generateMockPortfolio()
                
                let url: URL
                switch exportType {
                case .transactions:
                    url = try await exportService.exportTransactions(transactions, format: selectedFormat)
                case .portfolio:
                    url = try await exportService.exportPortfolio(portfolio, format: selectedFormat)
                case .both:
                    // Export both to same folder
                    _ = try await exportService.exportTransactions(transactions, format: selectedFormat)
                    url = try await exportService.exportPortfolio(portfolio, format: selectedFormat)
                }
                
                await MainActor.run {
                    exportedURL = url
                    isExporting = false
                    withAnimation(.spring(response: 0.3)) {
                        showSuccess = true
                    }
                }
            } catch {
                await MainActor.run {
                    isExporting = false
                    // Show error
                }
            }
        }
    }
    
    // MARK: - Mock Data Generation
    
    private func generateMockTransactions() -> [ExportService.ExportTransaction] {
        let types = ["Send", "Receive", "Swap"]
        let assets = ["BTC", "ETH", "SOL", "XRP", "LTC"]
        let statuses = ["Confirmed", "Pending"]
        
        return (0..<estimatedRecords).map { i in
            let date = Date().addingTimeInterval(TimeInterval(-i * 86400 / 10))
            let dateStr = DateFormatter.localizedString(from: date, dateStyle: .short, timeStyle: .short)
            let asset = assets[i % assets.count]
            let amount = Double.random(in: 0.001...5.0)
            
            return ExportService.ExportTransaction(
                date: dateStr,
                type: types[i % types.count],
                asset: asset,
                amount: String(format: "%.6f %@", amount, asset),
                valueUSD: String(format: "$%.2f", amount * Double.random(in: 100...50000)),
                fee: String(format: "$%.2f", Double.random(in: 0.1...5.0)),
                txHash: UUID().uuidString.replacingOccurrences(of: "-", with: "").prefix(64).description,
                fromAddress: "0x\(UUID().uuidString.replacingOccurrences(of: "-", with: "").prefix(40))",
                toAddress: "0x\(UUID().uuidString.replacingOccurrences(of: "-", with: "").prefix(40))",
                status: statuses[i % statuses.count],
                network: asset == "ETH" ? "Ethereum" : asset,
                blockNumber: 18000000 + i,
                confirmations: i % 2 == 0 ? 100 + i : nil
            )
        }
    }
    
    private func generateMockPortfolio() -> ExportService.ExportPortfolio {
        let dateStr = DateFormatter.localizedString(from: Date(), dateStyle: .long, timeStyle: .short)
        
        return ExportService.ExportPortfolio(
            exportDate: dateStr,
            totalValueUSD: "$15,234.56",
            assets: [
                ExportService.ExportAsset(symbol: "BTC", name: "Bitcoin", balance: "0.15234", valueUSD: "$9,234.56", price: "$60,612.34", change24h: "+2.34%", allocation: "60.6%"),
                ExportService.ExportAsset(symbol: "ETH", name: "Ethereum", balance: "1.5678", valueUSD: "$4,567.89", price: "$2,912.45", change24h: "+1.23%", allocation: "30.0%"),
                ExportService.ExportAsset(symbol: "SOL", name: "Solana", balance: "12.345", valueUSD: "$1,234.56", price: "$100.00", change24h: "-0.87%", allocation: "8.1%"),
                ExportService.ExportAsset(symbol: "XRP", name: "Ripple", balance: "500.00", valueUSD: "$197.55", price: "$0.395", change24h: "+5.67%", allocation: "1.3%")
            ]
        )
    }
}

// MARK: - Preview

#if DEBUG
struct ExportView_Previews: PreviewProvider {
    static var previews: some View {
        ExportView()
            .preferredColorScheme(.dark)
    }
}
#endif
