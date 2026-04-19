import Foundation
import AppKit
import UniformTypeIdentifiers

// MARK: - Export Service

/// Service for exporting transaction history and portfolio data
@MainActor
final class ExportService: ObservableObject {
    static let shared = ExportService()
    
    // MARK: - Export Formats
    
    enum ExportFormat: String, CaseIterable {
        case csv = "CSV"
        case json = "JSON"
        case pdf = "PDF"
        
        var fileExtension: String {
            rawValue.lowercased()
        }
        
        var utType: UTType {
            switch self {
            case .csv: return .commaSeparatedText
            case .json: return .json
            case .pdf: return .pdf
            }
        }
        
        var icon: String {
            switch self {
            case .csv: return "tablecells"
            case .json: return "curlybraces"
            case .pdf: return "doc.richtext"
            }
        }
    }
    
    // MARK: - Export Data Types
    
    struct ExportTransaction: Codable {
        let date: String
        let type: String
        let asset: String
        let amount: String
        let valueUSD: String?
        let fee: String?
        let txHash: String?
        let fromAddress: String?
        let toAddress: String?
        let status: String
        let network: String
        let blockNumber: Int?
        let confirmations: Int?
    }
    
    struct ExportPortfolio: Codable {
        let exportDate: String
        let totalValueUSD: String
        let assets: [ExportAsset]
    }
    
    struct ExportAsset: Codable {
        let symbol: String
        let name: String
        let balance: String
        let valueUSD: String
        let price: String
        let change24h: String
        let allocation: String
    }
    
    // MARK: - Published Properties
    
    @Published var isExporting = false
    @Published var lastExportPath: URL?
    @Published var exportError: String?
    
    // MARK: - Private Properties
    
    private let dateFormatter: DateFormatter = {
        let df = DateFormatter()
        df.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return df
    }()
    
    private let fileDateFormatter: DateFormatter = {
        let df = DateFormatter()
        df.dateFormat = "yyyy-MM-dd_HHmmss"
        return df
    }()
    
    private init() {}
    
    // MARK: - Export Methods
    
    /// Export transactions to specified format
    func exportTransactions(
        _ transactions: [ExportTransaction],
        format: ExportFormat,
        filename: String? = nil
    ) async throws -> URL {
        isExporting = true
        exportError = nil
        
        defer { isExporting = false }
        
        let data: Data
        switch format {
        case .csv:
            data = try generateTransactionCSV(transactions)
        case .json:
            data = try generateTransactionJSON(transactions)
        case .pdf:
            data = try generateTransactionPDF(transactions)
        }
        
        let fileName = filename ?? "hawala_transactions_\(fileDateFormatter.string(from: Date()))"
        let url = try saveToFile(data: data, fileName: fileName, extension: format.fileExtension)
        
        lastExportPath = url
        return url
    }
    
    /// Export portfolio snapshot
    func exportPortfolio(
        _ portfolio: ExportPortfolio,
        format: ExportFormat,
        filename: String? = nil
    ) async throws -> URL {
        isExporting = true
        exportError = nil
        
        defer { isExporting = false }
        
        let data: Data
        switch format {
        case .csv:
            data = try generatePortfolioCSV(portfolio)
        case .json:
            data = try generatePortfolioJSON(portfolio)
        case .pdf:
            data = try generatePortfolioPDF(portfolio)
        }
        
        let fileName = filename ?? "hawala_portfolio_\(fileDateFormatter.string(from: Date()))"
        let url = try saveToFile(data: data, fileName: fileName, extension: format.fileExtension)
        
        lastExportPath = url
        return url
    }
    
    /// Show save dialog and export
    func exportWithDialog(
        transactions: [ExportTransaction]? = nil,
        portfolio: ExportPortfolio? = nil,
        format: ExportFormat
    ) async {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [format.utType]
        panel.canCreateDirectories = true
        
        let defaultName: String
        if transactions != nil {
            defaultName = "hawala_transactions_\(fileDateFormatter.string(from: Date()))"
        } else {
            defaultName = "hawala_portfolio_\(fileDateFormatter.string(from: Date()))"
        }
        panel.nameFieldStringValue = "\(defaultName).\(format.fileExtension)"
        
        let response = await panel.beginSheetModal(for: NSApp.keyWindow ?? NSWindow())
        
        guard response == .OK, let url = panel.url else { return }
        
        do {
            let data: Data
            if let transactions = transactions {
                switch format {
                case .csv: data = try generateTransactionCSV(transactions)
                case .json: data = try generateTransactionJSON(transactions)
                case .pdf: data = try generateTransactionPDF(transactions)
                }
            } else if let portfolio = portfolio {
                switch format {
                case .csv: data = try generatePortfolioCSV(portfolio)
                case .json: data = try generatePortfolioJSON(portfolio)
                case .pdf: data = try generatePortfolioPDF(portfolio)
                }
            } else {
                throw ExportError.noData
            }
            
            try data.write(to: url)
            lastExportPath = url
            
            // Open in Finder
            NSWorkspace.shared.selectFile(url.path, inFileViewerRootedAtPath: url.deletingLastPathComponent().path)
            
        } catch {
            exportError = error.localizedDescription
        }
    }
    
    // MARK: - CSV Generation
    
    private func generateTransactionCSV(_ transactions: [ExportTransaction]) throws -> Data {
        var csv = "Date,Type,Asset,Amount,Value (USD),Fee,TX Hash,From,To,Status,Network,Block,Confirmations\n"
        
        for tx in transactions {
            let row = [
                tx.date,
                tx.type,
                tx.asset,
                tx.amount,
                tx.valueUSD ?? "",
                tx.fee ?? "",
                tx.txHash ?? "",
                tx.fromAddress ?? "",
                tx.toAddress ?? "",
                tx.status,
                tx.network,
                tx.blockNumber.map { String($0) } ?? "",
                tx.confirmations.map { String($0) } ?? ""
            ].map { escapeCSV($0) }.joined(separator: ",")
            
            csv += row + "\n"
        }
        
        guard let data = csv.data(using: .utf8) else {
            throw ExportError.encodingFailed
        }
        
        return data
    }
    
    private func generatePortfolioCSV(_ portfolio: ExportPortfolio) throws -> Data {
        var csv = "Symbol,Name,Balance,Value (USD),Price,24h Change,Allocation %\n"
        
        for asset in portfolio.assets {
            let row = [
                asset.symbol,
                asset.name,
                asset.balance,
                asset.valueUSD,
                asset.price,
                asset.change24h,
                asset.allocation
            ].map { escapeCSV($0) }.joined(separator: ",")
            
            csv += row + "\n"
        }
        
        csv += "\n"
        csv += "Export Date,\(portfolio.exportDate)\n"
        csv += "Total Value,\(portfolio.totalValueUSD)\n"
        
        guard let data = csv.data(using: .utf8) else {
            throw ExportError.encodingFailed
        }
        
        return data
    }
    
    private func escapeCSV(_ field: String) -> String {
        if field.contains(",") || field.contains("\"") || field.contains("\n") {
            return "\"\(field.replacingOccurrences(of: "\"", with: "\"\""))\""
        }
        return field
    }
    
    // MARK: - JSON Generation
    
    private func generateTransactionJSON(_ transactions: [ExportTransaction]) throws -> Data {
        let wrapper = TransactionExportWrapper(
            exportDate: dateFormatter.string(from: Date()),
            exportedBy: "Hawala Wallet",
            version: "2.0",
            transactionCount: transactions.count,
            transactions: transactions
        )
        
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(wrapper)
    }
    
    private func generatePortfolioJSON(_ portfolio: ExportPortfolio) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(portfolio)
    }
    
    // MARK: - PDF Generation
    
    private func generateTransactionPDF(_ transactions: [ExportTransaction]) throws -> Data {
        let pdfData = NSMutableData()
        
        // Page size: Letter
        var mediaBox = CGRect(x: 0, y: 0, width: 612, height: 792)
        
        guard let consumer = CGDataConsumer(data: pdfData as CFMutableData),
              let pdfContext = CGContext(consumer: consumer, mediaBox: &mediaBox, nil) else {
            throw ExportError.pdfGenerationFailed
        }
        
        let pageHeight: CGFloat = 792
        let pageWidth: CGFloat = 612
        let margin: CGFloat = 50
        var yPosition: CGFloat = pageHeight - margin
        let lineHeight: CGFloat = 20
        
        func startNewPage() {
            if yPosition < pageHeight - margin {
                pdfContext.endPage()
            }
            pdfContext.beginPage(mediaBox: &mediaBox)
            yPosition = pageHeight - margin
        }
        
        func drawText(_ text: String, x: CGFloat, y: CGFloat, fontSize: CGFloat = 10, bold: Bool = false) {
            let font = bold ? NSFont.boldSystemFont(ofSize: fontSize) : NSFont.systemFont(ofSize: fontSize)
            let attributes: [NSAttributedString.Key: Any] = [
                .font: font,
                .foregroundColor: NSColor.black
            ]
            let attributedString = NSAttributedString(string: text, attributes: attributes)
            let line = CTLineCreateWithAttributedString(attributedString)
            
            pdfContext.saveGState()
            pdfContext.textMatrix = CGAffineTransform(scaleX: 1, y: -1)
            pdfContext.textPosition = CGPoint(x: x, y: pageHeight - y)
            CTLineDraw(line, pdfContext)
            pdfContext.restoreGState()
        }
        
        // Start first page
        startNewPage()
        
        // Title
        drawText("Hawala Wallet - Transaction History", x: margin, y: yPosition, fontSize: 18, bold: true)
        yPosition -= 30
        
        // Export info
        drawText("Exported: \(dateFormatter.string(from: Date()))", x: margin, y: yPosition, fontSize: 10)
        yPosition -= 15
        drawText("Total Transactions: \(transactions.count)", x: margin, y: yPosition, fontSize: 10)
        yPosition -= 30
        
        // Table header
        let columns: [(String, CGFloat)] = [
            ("Date", margin),
            ("Type", margin + 100),
            ("Asset", margin + 150),
            ("Amount", margin + 200),
            ("Status", margin + 300),
            ("TX Hash", margin + 360)
        ]
        
        for (title, x) in columns {
            drawText(title, x: x, y: yPosition, fontSize: 9, bold: true)
        }
        yPosition -= lineHeight
        
        // Draw line
        pdfContext.setStrokeColor(NSColor.gray.cgColor)
        pdfContext.setLineWidth(0.5)
        pdfContext.move(to: CGPoint(x: margin, y: pageHeight - yPosition + 5))
        pdfContext.addLine(to: CGPoint(x: pageWidth - margin, y: pageHeight - yPosition + 5))
        pdfContext.strokePath()
        yPosition -= 5
        
        // Transactions
        for tx in transactions {
            if yPosition < margin + 50 {
                startNewPage()
                yPosition -= 30
            }
            
            drawText(String(tx.date.prefix(10)), x: columns[0].1, y: yPosition, fontSize: 8)
            drawText(tx.type, x: columns[1].1, y: yPosition, fontSize: 8)
            drawText(tx.asset, x: columns[2].1, y: yPosition, fontSize: 8)
            drawText(tx.amount, x: columns[3].1, y: yPosition, fontSize: 8)
            drawText(tx.status, x: columns[4].1, y: yPosition, fontSize: 8)
            drawText(String((tx.txHash ?? "").prefix(12)) + "...", x: columns[5].1, y: yPosition, fontSize: 7)
            
            yPosition -= lineHeight
        }
        
        // Footer
        yPosition = margin
        drawText("Generated by Hawala Wallet v2.0", x: margin, y: yPosition, fontSize: 8)
        
        pdfContext.endPage()
        pdfContext.closePDF()
        
        return pdfData as Data
    }
    
    private func generatePortfolioPDF(_ portfolio: ExportPortfolio) throws -> Data {
        let pdfData = NSMutableData()
        var mediaBox = CGRect(x: 0, y: 0, width: 612, height: 792)
        
        guard let consumer = CGDataConsumer(data: pdfData as CFMutableData),
              let pdfContext = CGContext(consumer: consumer, mediaBox: &mediaBox, nil) else {
            throw ExportError.pdfGenerationFailed
        }
        
        let pageHeight: CGFloat = 792
        let margin: CGFloat = 50
        var yPosition: CGFloat = pageHeight - margin
        let lineHeight: CGFloat = 25
        
        pdfContext.beginPage(mediaBox: &mediaBox)
        
        func drawText(_ text: String, x: CGFloat, y: CGFloat, fontSize: CGFloat = 10, bold: Bool = false) {
            let font = bold ? NSFont.boldSystemFont(ofSize: fontSize) : NSFont.systemFont(ofSize: fontSize)
            let attributes: [NSAttributedString.Key: Any] = [
                .font: font,
                .foregroundColor: NSColor.black
            ]
            let attributedString = NSAttributedString(string: text, attributes: attributes)
            let line = CTLineCreateWithAttributedString(attributedString)
            
            pdfContext.saveGState()
            pdfContext.textMatrix = CGAffineTransform(scaleX: 1, y: -1)
            pdfContext.textPosition = CGPoint(x: x, y: pageHeight - y)
            CTLineDraw(line, pdfContext)
            pdfContext.restoreGState()
        }
        
        // Title
        drawText("Hawala Wallet - Portfolio Snapshot", x: margin, y: yPosition, fontSize: 18, bold: true)
        yPosition -= 30
        
        // Summary
        drawText("Export Date: \(portfolio.exportDate)", x: margin, y: yPosition, fontSize: 11)
        yPosition -= 20
        drawText("Total Portfolio Value: \(portfolio.totalValueUSD)", x: margin, y: yPosition, fontSize: 14, bold: true)
        yPosition -= 40
        
        // Table header
        let columns: [(String, CGFloat)] = [
            ("Asset", margin),
            ("Balance", margin + 100),
            ("Price", margin + 200),
            ("Value", margin + 300),
            ("24h %", margin + 400),
            ("Alloc", margin + 460)
        ]
        
        for (title, x) in columns {
            drawText(title, x: x, y: yPosition, fontSize: 10, bold: true)
        }
        yPosition -= lineHeight
        
        // Assets
        for asset in portfolio.assets {
            drawText("\(asset.symbol) (\(asset.name))", x: columns[0].1, y: yPosition, fontSize: 9)
            drawText(asset.balance, x: columns[1].1, y: yPosition, fontSize: 9)
            drawText(asset.price, x: columns[2].1, y: yPosition, fontSize: 9)
            drawText(asset.valueUSD, x: columns[3].1, y: yPosition, fontSize: 9)
            drawText(asset.change24h, x: columns[4].1, y: yPosition, fontSize: 9)
            drawText(asset.allocation, x: columns[5].1, y: yPosition, fontSize: 9)
            
            yPosition -= lineHeight
        }
        
        // Footer
        yPosition = margin
        drawText("Generated by Hawala Wallet v2.0", x: margin, y: yPosition, fontSize: 8)
        
        pdfContext.endPage()
        pdfContext.closePDF()
        
        return pdfData as Data
    }
    
    // MARK: - File Operations
    
    private func saveToFile(data: Data, fileName: String, extension ext: String) throws -> URL {
        let fileManager = FileManager.default
        let documentsURL = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first!
        let hawalaFolder = documentsURL.appendingPathComponent("Hawala Exports", isDirectory: true)
        
        // Create folder if needed
        if !fileManager.fileExists(atPath: hawalaFolder.path) {
            try fileManager.createDirectory(at: hawalaFolder, withIntermediateDirectories: true)
        }
        
        let fileURL = hawalaFolder.appendingPathComponent("\(fileName).\(ext)")
        try data.write(to: fileURL)
        
        return fileURL
    }
}

// MARK: - Supporting Types

private struct TransactionExportWrapper: Codable {
    let exportDate: String
    let exportedBy: String
    let version: String
    let transactionCount: Int
    let transactions: [ExportService.ExportTransaction]
}

enum ExportError: Error, LocalizedError {
    case noData
    case encodingFailed
    case pdfGenerationFailed
    case fileWriteFailed
    
    var errorDescription: String? {
        switch self {
        case .noData: return "No data to export"
        case .encodingFailed: return "Failed to encode data"
        case .pdfGenerationFailed: return "Failed to generate PDF"
        case .fileWriteFailed: return "Failed to write file"
        }
    }
}
