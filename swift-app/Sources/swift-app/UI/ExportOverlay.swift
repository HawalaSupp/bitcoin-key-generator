import SwiftUI
import AppKit

// MARK: - Export Overlay

struct ExportOverlay: View {
    @Binding var isPresented: Bool
    var onBackToSettings: (() -> Void)? = nil

    // ── Tab enum ──
    enum ExportTab: String, CaseIterable {
        case export = "EXPORT"
        case log = "LOG"
    }

    // ── Date range ──
    enum DateRange: String, CaseIterable {
        case week = "7 Days"
        case month = "30 Days"
        case quarter = "90 Days"
        case year = "1 Year"
        case all = "All"

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

    // ── Export fields ──
    enum ExportField: String, CaseIterable {
        case date = "Date"
        case type = "Type"
        case asset = "Asset"
        case amount = "Amount"
        case fee = "Fee"
        case txHash = "Tx Hash"
        case addresses = "Addresses"
        case status = "Status"
        case network = "Network"
    }

    // ── Services ──
    private let transactionService = TransactionHistoryService.shared
    @ObservedObject private var exportService = ExportService.shared

    // ── UI state ──
    @State private var activeTab: ExportTab = .export
    @State private var contentOpacity: Double = 0
    @State private var cardScale: CGFloat = 0.92
    @State private var silkPhase: CGFloat = 0
    @State private var closeHovered = false

    // ── Export form state ──
    @State private var selectedFormat: ExportService.ExportFormat = .csv
    @State private var selectedRange: DateRange = .all
    @State private var selectedFields: Set<ExportField> = Set(ExportField.allCases)
    @State private var includeNotes: Bool = true

    // ── Export progress state ──
    @State private var isExporting = false
    @State private var exportComplete = false
    @State private var exportError: String?
    @State private var lastExportFilename: String?
    @State private var lastExportURL: URL?
    @State private var lastExportCount: Int = 0

    // ── Log state ──
    @AppStorage("hawala.exportLog") private var exportLogData: Data = Data()

    var body: some View {
        ZStack {
            backdrop
            mainCard
        }
        .background(EscapeKeyHandler(isPresented: $isPresented, onEscape: dismissOverlay))
        .onAppear {
            withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                cardScale = 1
                contentOpacity = 1
            }
            withAnimation(.linear(duration: 5).repeatForever(autoreverses: false)) {
                silkPhase = 1
            }
        }
    }

    // MARK: - Backdrop

    private var backdrop: some View {
        Color.black.opacity(0.75)
            .ignoresSafeArea()
            .onTapGesture { dismissOverlay() }
    }

    // MARK: - Main Card

    private var mainCard: some View {
        VStack(spacing: 0) {
            headerBar
            tabPicker
            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: 20) {
                    tabContent
                }
                .padding(.horizontal, 28)
                .padding(.top, 4)
                .padding(.bottom, 28)
            }
        }
        .frame(width: 700, height: 650)
        .background(cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(cardStroke)
        .shadow(color: .black.opacity(0.5), radius: 50, y: 25)
        .scaleEffect(cardScale)
        .opacity(contentOpacity)
    }

    // MARK: - Header

    private var headerBar: some View {
        HStack {
            Button(action: {
                dismissOverlay()
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                    onBackToSettings?()
                }
            }) {
                HStack(spacing: 4) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 10, weight: .semibold))
                    Text("Settings")
                        .font(.system(size: 11, weight: .medium))
                }
                .foregroundColor(.white.opacity(0.4))
            }
            .buttonStyle(.plain)

            Spacer()

            Text("Export History")
                .font(.system(size: 15, weight: .semibold, design: .rounded))
                .foregroundColor(.white.opacity(0.9))

            Spacer()

            Button(action: dismissOverlay) {
                Image(systemName: "xmark")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(closeHovered ? .white.opacity(0.9) : .white.opacity(0.4))
                    .frame(width: 28, height: 28)
                    .background(closeHovered ? Color.white.opacity(0.1) : Color.clear)
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)
            .onHover { closeHovered = $0 }
        }
        .padding(.horizontal, 24)
        .padding(.top, 20)
        .padding(.bottom, 12)
    }

    // MARK: - Tab Picker

    private var tabPicker: some View {
        HStack(spacing: 0) {
            ForEach(ExportTab.allCases, id: \.self) { tab in
                Button(action: {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
                        activeTab = tab
                    }
                }) {
                    Text(tab.rawValue)
                        .font(.system(size: 10, weight: .semibold, design: .monospaced))
                        .tracking(1)
                        .foregroundColor(activeTab == tab ? .white.opacity(0.9) : .white.opacity(0.35))
                        .padding(.horizontal, 16)
                        .padding(.vertical, 7)
                        .background(
                            activeTab == tab
                            ? Color.white.opacity(0.08)
                            : Color.clear
                        )
                        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 24)
        .padding(.bottom, 8)
    }

    // MARK: - Tab Content

    @ViewBuilder
    private var tabContent: some View {
        switch activeTab {
        case .export:
            exportTabContent
                .transition(.opacity.combined(with: .move(edge: .top)))
        case .log:
            logTabContent
                .transition(.opacity.combined(with: .move(edge: .top)))
        }
    }

    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    // MARK: - EXPORT TAB
    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

    @ViewBuilder
    private var exportTabContent: some View {
        if exportComplete {
            exportSuccessView
        } else {
            formatSection
            dateRangeSection
            fieldSelectionSection
            notesToggleSection
            previewSection
            exportButton
            if let error = exportError {
                errorBanner(error)
            }
        }
    }

    // MARK: - Format Section

    private var formatSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionLabel("FORMAT")

            HStack(spacing: 8) {
                ForEach(ExportService.ExportFormat.allCases, id: \.self) { format in
                    Button(action: { selectedFormat = format }) {
                        HStack(spacing: 6) {
                            Image(systemName: format.icon)
                                .font(.system(size: 11))
                            Text(format.rawValue)
                                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                        }
                        .foregroundColor(selectedFormat == format ? .white.opacity(0.9) : .white.opacity(0.4))
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .background(
                            selectedFormat == format
                            ? Color.white.opacity(0.12)
                            : Color.white.opacity(0.04)
                        )
                        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .strokeBorder(
                                    selectedFormat == format
                                    ? Color.white.opacity(0.15)
                                    : Color.white.opacity(0.06),
                                    lineWidth: 1
                                )
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(16)
        .background(Color.white.opacity(0.03))
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    // MARK: - Date Range Section

    private var dateRangeSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionLabel("DATE RANGE")

            HStack(spacing: 6) {
                ForEach(DateRange.allCases, id: \.self) { range in
                    Button(action: { selectedRange = range }) {
                        Text(range.rawValue)
                            .font(.system(size: 10, weight: .semibold, design: .monospaced))
                            .foregroundColor(selectedRange == range ? .white.opacity(0.9) : .white.opacity(0.4))
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(
                                selectedRange == range
                                ? Color.white.opacity(0.12)
                                : Color.white.opacity(0.04)
                            )
                            .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(16)
        .background(Color.white.opacity(0.03))
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    // MARK: - Field Selection Section

    private var fieldSelectionSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                sectionLabel("FIELDS")
                Spacer()
                Button(action: {
                    if selectedFields.count == ExportField.allCases.count {
                        selectedFields = [.date, .type, .asset, .amount, .status]
                    } else {
                        selectedFields = Set(ExportField.allCases)
                    }
                }) {
                    Text(selectedFields.count == ExportField.allCases.count ? "Minimal" : "Select All")
                        .font(.system(size: 9, weight: .semibold, design: .monospaced))
                        .foregroundColor(.white.opacity(0.35))
                }
                .buttonStyle(.plain)
            }

            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 3), spacing: 8) {
                ForEach(ExportField.allCases, id: \.self) { field in
                    Button(action: {
                        if selectedFields.contains(field) {
                            if selectedFields.count > 1 {
                                selectedFields.remove(field)
                            }
                        } else {
                            selectedFields.insert(field)
                        }
                    }) {
                        HStack(spacing: 6) {
                            Image(systemName: selectedFields.contains(field) ? "checkmark.square.fill" : "square")
                                .font(.system(size: 11))
                                .foregroundColor(selectedFields.contains(field) ? .white.opacity(0.7) : .white.opacity(0.2))
                            Text(field.rawValue)
                                .font(.system(size: 10, weight: .medium))
                                .foregroundColor(selectedFields.contains(field) ? .white.opacity(0.7) : .white.opacity(0.3))
                            Spacer()
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(
                            selectedFields.contains(field)
                            ? Color.white.opacity(0.06)
                            : Color.white.opacity(0.02)
                        )
                        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(16)
        .background(Color.white.opacity(0.03))
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    // MARK: - Notes Toggle

    private var notesToggleSection: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("Include Notes")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.white.opacity(0.7))
                Text("Add transaction notes as an extra column")
                    .font(.system(size: 10))
                    .foregroundColor(.white.opacity(0.3))
            }
            Spacer()
            Toggle("", isOn: $includeNotes)
                .toggleStyle(.switch)
                .scaleEffect(0.7)
                .frame(width: 40)
        }
        .padding(16)
        .background(Color.white.opacity(0.03))
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    // MARK: - Preview Section

    private var previewSection: some View {
        let entries = filteredEntries
        let count = entries.count

        return HStack(spacing: 16) {
            previewItem(
                icon: "doc.text",
                label: "Records",
                value: "\(count)"
            )
            previewItem(
                icon: selectedFormat.icon,
                label: "Format",
                value: selectedFormat.rawValue
            )
            previewItem(
                icon: "calendar",
                label: "Range",
                value: selectedRange.rawValue
            )
            previewItem(
                icon: "checklist",
                label: "Fields",
                value: "\(selectedFields.count + (includeNotes ? 1 : 0))"
            )
        }
        .padding(16)
        .background(Color.white.opacity(0.03))
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private func previewItem(icon: String, label: String, value: String) -> some View {
        VStack(spacing: 4) {
            Image(systemName: icon)
                .font(.system(size: 13))
                .foregroundColor(.white.opacity(0.35))
            Text(value)
                .font(.system(size: 14, weight: .semibold, design: .monospaced))
                .foregroundColor(.white.opacity(0.85))
            Text(label)
                .font(.system(size: 9))
                .foregroundColor(.white.opacity(0.3))
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Export Button

    private var exportButton: some View {
        Button(action: { Task { await performExport() } }) {
            HStack(spacing: 8) {
                if isExporting {
                    ProgressView()
                        .scaleEffect(0.6)
                        .frame(width: 14, height: 14)
                } else {
                    Image(systemName: "square.and.arrow.up")
                        .font(.system(size: 12, weight: .semibold))
                }
                Text(isExporting ? "Exporting..." : "Export \(filteredEntries.count) Transactions")
                    .font(.system(size: 12, weight: .semibold))
            }
            .foregroundColor(.white.opacity(isExporting ? 0.5 : 0.9))
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background(Color.white.opacity(isExporting ? 0.06 : 0.10))
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.08), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .disabled(isExporting || filteredEntries.isEmpty)
    }

    // MARK: - Success View

    private var exportSuccessView: some View {
        VStack(spacing: 24) {
            Spacer().frame(height: 40)

            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 48))
                .foregroundColor(.green.opacity(0.7))

            VStack(spacing: 6) {
                Text("Export Complete")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(.white.opacity(0.9))

                if let filename = lastExportFilename {
                    Text(filename)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundColor(.white.opacity(0.4))
                }

                Text("\(lastExportCount) transactions exported as \(selectedFormat.rawValue)")
                    .font(.system(size: 11))
                    .foregroundColor(.white.opacity(0.35))
            }

            HStack(spacing: 12) {
                if let url = lastExportURL {
                    Button(action: {
                        NSWorkspace.shared.selectFile(
                            url.path,
                            inFileViewerRootedAtPath: url.deletingLastPathComponent().path
                        )
                    }) {
                        HStack(spacing: 6) {
                            Image(systemName: "folder")
                                .font(.system(size: 11))
                            Text("Show in Finder")
                                .font(.system(size: 11, weight: .semibold))
                        }
                        .foregroundColor(.white.opacity(0.7))
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .background(Color.white.opacity(0.08))
                        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                    }
                    .buttonStyle(.plain)
                }

                Button(action: {
                    exportComplete = false
                    exportError = nil
                }) {
                    Text("Done")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(.white.opacity(0.5))
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .background(Color.white.opacity(0.04))
                        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                }
                .buttonStyle(.plain)
            }

            Spacer()
        }
    }

    // MARK: - Error Banner

    private func errorBanner(_ message: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 11))
                .foregroundColor(.red.opacity(0.7))
            Text(message)
                .font(.system(size: 11))
                .foregroundColor(.red.opacity(0.7))
            Spacer()
            Button(action: { exportError = nil }) {
                Image(systemName: "xmark")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundColor(.white.opacity(0.3))
            }
            .buttonStyle(.plain)
        }
        .padding(12)
        .background(Color.red.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    // MARK: - LOG TAB
    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

    private var logTabContent: some View {
        VStack(spacing: 12) {
            let log = loadExportLog()

            if log.isEmpty {
                VStack(spacing: 12) {
                    Spacer().frame(height: 60)
                    Image(systemName: "clock.arrow.circlepath")
                        .font(.system(size: 32))
                        .foregroundColor(.white.opacity(0.15))
                    Text("No exports yet")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(.white.opacity(0.3))
                    Text("Your export history will appear here")
                        .font(.system(size: 11))
                        .foregroundColor(.white.opacity(0.2))
                    Spacer()
                }
            } else {
                HStack {
                    sectionLabel("RECENT EXPORTS")
                    Spacer()
                    Button(action: clearExportLog) {
                        Text("CLEAR")
                            .font(.system(size: 9, weight: .semibold, design: .monospaced))
                            .tracking(0.5)
                            .foregroundColor(.white.opacity(0.3))
                    }
                    .buttonStyle(.plain)
                }

                ForEach(log.reversed()) { entry in
                    logRow(entry)
                }
            }
        }
    }

    private func logRow(_ entry: ExportLogEntry) -> some View {
        HStack(spacing: 12) {
            Image(systemName: iconForFormat(entry.format))
                .font(.system(size: 13))
                .foregroundColor(.white.opacity(0.35))
                .frame(width: 28, height: 28)
                .background(Color.white.opacity(0.04))
                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))

            VStack(alignment: .leading, spacing: 2) {
                Text(entry.filename)
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .foregroundColor(.white.opacity(0.7))
                    .lineLimit(1)
                HStack(spacing: 8) {
                    Text(entry.format.uppercased())
                        .font(.system(size: 9, weight: .semibold, design: .monospaced))
                        .foregroundColor(.white.opacity(0.35))
                    Text("\(entry.recordCount) records")
                        .font(.system(size: 9))
                        .foregroundColor(.white.opacity(0.25))
                }
            }

            Spacer()

            Text(entry.formattedDate)
                .font(.system(size: 10, design: .monospaced))
                .foregroundColor(.white.opacity(0.25))
        }
        .padding(12)
        .background(Color.white.opacity(0.03))
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private func iconForFormat(_ format: String) -> String {
        switch format.lowercased() {
        case "csv": return "tablecells"
        case "json": return "curlybraces"
        case "pdf": return "doc.richtext"
        default: return "doc"
        }
    }

    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    // MARK: - Data Bridge
    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

    /// Get filtered transaction entries based on selected date range
    private var filteredEntries: [HawalaTransactionEntry] {
        let all = transactionService.hawalaEntries
        guard let days = selectedRange.days else { return all }
        let cutoff = Date().timeIntervalSince1970 - Double(days * 86400)
        return all.filter { ($0.sortTimestamp ?? 0) >= cutoff }
    }

    /// Convert HawalaTransactionEntry → ExportService.ExportTransaction
    private func convertToExportTransaction(_ entry: HawalaTransactionEntry) -> ExportService.ExportTransaction {
        let fromAddress: String?
        let toAddress: String?

        if entry.type.lowercased() == "send" {
            fromAddress = nil
            toAddress = entry.counterparty
        } else if entry.type.lowercased() == "receive" {
            fromAddress = entry.counterparty
            toAddress = nil
        } else {
            fromAddress = nil
            toAddress = entry.counterparty
        }

        return ExportService.ExportTransaction(
            date: entry.timestamp,
            type: entry.type,
            asset: entry.asset,
            amount: entry.amountDisplay,
            valueUSD: nil,
            fee: selectedFields.contains(.fee) ? entry.fee : nil,
            txHash: selectedFields.contains(.txHash) ? entry.txHash : nil,
            fromAddress: selectedFields.contains(.addresses) ? fromAddress : nil,
            toAddress: selectedFields.contains(.addresses) ? toAddress : nil,
            status: entry.status,
            network: entry.chainId ?? "unknown",
            blockNumber: entry.blockNumber,
            confirmations: entry.confirmations
        )
    }

    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    // MARK: - Export Logic
    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

    private func performExport() async {
        let entries = filteredEntries
        guard !entries.isEmpty else {
            exportError = "No transactions to export"
            return
        }

        isExporting = true
        exportError = nil

        let converted = entries.map { convertToExportTransaction($0) }

        // Use ExportService's dialog-based export
        await exportService.exportWithDialog(
            transactions: converted,
            portfolio: nil,
            format: selectedFormat
        )

        isExporting = false

        if let error = exportService.exportError {
            exportError = error
        } else if let url = exportService.lastExportPath {
            lastExportURL = url
            lastExportFilename = url.lastPathComponent
            lastExportCount = entries.count
            exportComplete = true

            // Log the export
            appendToExportLog(ExportLogEntry(
                id: UUID().uuidString,
                date: Date().timeIntervalSince1970,
                format: selectedFormat.rawValue.lowercased(),
                filename: url.lastPathComponent,
                recordCount: entries.count
            ))
        }
    }

    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    // MARK: - Export Log Persistence
    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

    private func loadExportLog() -> [ExportLogEntry] {
        guard !exportLogData.isEmpty else { return [] }
        return (try? JSONDecoder().decode([ExportLogEntry].self, from: exportLogData)) ?? []
    }

    private func appendToExportLog(_ entry: ExportLogEntry) {
        var log = loadExportLog()
        log.append(entry)
        // Keep last 50 entries
        if log.count > 50 { log = Array(log.suffix(50)) }
        if let data = try? JSONEncoder().encode(log) {
            exportLogData = data
        }
    }

    private func clearExportLog() {
        exportLogData = Data()
    }

    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    // MARK: - Card Chrome
    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

    private var cardBackground: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(Color(red: 0.06, green: 0.06, blue: 0.07))
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(LinearGradient(
                    colors: [.clear, .white.opacity(0.015), .clear],
                    startPoint: UnitPoint(x: silkPhase - 0.3, y: 0),
                    endPoint: UnitPoint(x: silkPhase + 0.3, y: 1)
                ))
        }
    }

    private var cardStroke: some View {
        RoundedRectangle(cornerRadius: 20, style: .continuous)
            .strokeBorder(
                LinearGradient(
                    colors: [.white.opacity(0.10), .white.opacity(0.03)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ),
                lineWidth: 1
            )
    }

    // MARK: - Helpers

    private func sectionLabel(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 10, weight: .semibold, design: .monospaced))
            .tracking(1)
            .foregroundColor(.white.opacity(0.3))
    }

    private func dismissOverlay() {
        withAnimation(.spring(response: 0.25, dampingFraction: 0.9)) {
            cardScale = 0.95
            contentOpacity = 0
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            isPresented = false
        }
    }
}

// MARK: - Export Log Entry

struct ExportLogEntry: Codable, Identifiable {
    let id: String
    let date: TimeInterval
    let format: String
    let filename: String
    let recordCount: Int

    var formattedDate: String {
        let df = DateFormatter()
        df.dateFormat = "MMM d, HH:mm"
        return df.string(from: Date(timeIntervalSince1970: date))
    }
}
