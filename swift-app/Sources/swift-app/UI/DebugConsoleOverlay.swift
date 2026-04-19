import SwiftUI
import AppKit

// MARK: - Debug Console Overlay

struct DebugConsoleOverlay: View {
    @Binding var isPresented: Bool
    var onBackToSettings: (() -> Void)? = nil

    // ── Tab enum ──
    enum ConsoleTab: String, CaseIterable {
        case console = "CONSOLE"
        case network = "NETWORK"
        case system = "SYSTEM"
    }

    // ── Services ──
    @StateObject private var logger = DebugLogger.shared

    // ── UI state ──
    @State private var activeTab: ConsoleTab = .console
    @State private var contentOpacity: Double = 0
    @State private var cardScale: CGFloat = 0.92
    @State private var silkPhase: CGFloat = 0
    @State private var closeHovered = false

    // ── Console filters ──
    @State private var filterCategory: LogCategory? = nil
    @State private var filterLevel: LogLevel? = nil
    @State private var searchText: String = ""
    @State private var autoScroll: Bool = true
    @State private var showTimestamps: Bool = true

    // ── Network state ──
    @State private var selectedEndpoint: String? = nil

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
            tabContent
        }
        .frame(width: 750, height: 650)
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

            Text("Debug Console")
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
            ForEach(ConsoleTab.allCases, id: \.self) { tab in
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
        case .console:
            consoleTabContent
                .transition(.opacity.combined(with: .move(edge: .top)))
        case .network:
            networkTabContent
                .transition(.opacity.combined(with: .move(edge: .top)))
        case .system:
            systemTabContent
                .transition(.opacity.combined(with: .move(edge: .top)))
        }
    }

    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    // MARK: - CONSOLE TAB
    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

    private var consoleTabContent: some View {
        VStack(spacing: 0) {
            consoleToolbar
                .padding(.horizontal, 24)
                .padding(.vertical, 8)

            Divider().background(Color.white.opacity(0.06))

            if filteredEntries.isEmpty {
                consoleEmptyState
            } else {
                ScrollViewReader { proxy in
                    ScrollView(.vertical, showsIndicators: true) {
                        LazyVStack(alignment: .leading, spacing: 0) {
                            ForEach(filteredEntries) { entry in
                                logEntryRow(entry)
                                    .id(entry.id)
                            }
                        }
                        .padding(.vertical, 4)
                    }
                    .onChange(of: logger.entries.count) { _ in
                        if autoScroll, let last = filteredEntries.last {
                            withAnimation(.easeOut(duration: 0.15)) {
                                proxy.scrollTo(last.id, anchor: .bottom)
                            }
                        }
                    }
                }
            }
        }
    }

    private var consoleToolbar: some View {
        HStack(spacing: 8) {
            // Search
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 10))
                    .foregroundColor(.white.opacity(0.3))
                TextField("Filter logs...", text: $searchText)
                    .textFieldStyle(.plain)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundColor(.white.opacity(0.7))
                if !searchText.isEmpty {
                    Button(action: { searchText = "" }) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 10))
                            .foregroundColor(.white.opacity(0.3))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(Color.white.opacity(0.04))
            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))

            // Category filter
            Menu {
                Button(action: { filterCategory = nil }) {
                    HStack {
                        Text("All Categories")
                        if filterCategory == nil { Image(systemName: "checkmark") }
                    }
                }
                Divider()
                ForEach([LogCategory.general, .network, .wallet, .transaction, .security], id: \.self) { cat in
                    Button(action: { filterCategory = cat }) {
                        HStack {
                            Text(cat.rawValue.capitalized)
                            if filterCategory == cat { Image(systemName: "checkmark") }
                        }
                    }
                }
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "line.3.horizontal.decrease")
                        .font(.system(size: 10))
                    Text(filterCategory?.rawValue.capitalized ?? "All")
                        .font(.system(size: 10, weight: .medium, design: .monospaced))
                }
                .foregroundColor(filterCategory != nil ? .white.opacity(0.7) : .white.opacity(0.35))
                .padding(.horizontal, 8)
                .padding(.vertical, 5)
                .background(filterCategory != nil ? Color.white.opacity(0.08) : Color.white.opacity(0.04))
                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
            }

            // Level filter
            Menu {
                Button(action: { filterLevel = nil }) {
                    HStack {
                        Text("All Levels")
                        if filterLevel == nil { Image(systemName: "checkmark") }
                    }
                }
                Divider()
                ForEach([LogLevel.debug, .info, .warning, .error], id: \.self) { level in
                    Button(action: { filterLevel = level }) {
                        HStack {
                            Circle()
                                .fill(colorForLevel(level))
                                .frame(width: 8, height: 8)
                            Text(level.rawValue.uppercased())
                            if filterLevel == level { Image(systemName: "checkmark") }
                        }
                    }
                }
            } label: {
                HStack(spacing: 4) {
                    Circle()
                        .fill(filterLevel != nil ? colorForLevel(filterLevel!) : .white.opacity(0.25))
                        .frame(width: 6, height: 6)
                    Text(filterLevel?.rawValue.uppercased() ?? "Level")
                        .font(.system(size: 10, weight: .medium, design: .monospaced))
                }
                .foregroundColor(filterLevel != nil ? .white.opacity(0.7) : .white.opacity(0.35))
                .padding(.horizontal, 8)
                .padding(.vertical, 5)
                .background(filterLevel != nil ? Color.white.opacity(0.08) : Color.white.opacity(0.04))
                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
            }

            Spacer()

            // Entry count
            Text("\(filteredEntries.count)")
                .font(.system(size: 10, weight: .semibold, design: .monospaced))
                .foregroundColor(.white.opacity(0.3))

            // Auto-scroll toggle
            Button(action: { autoScroll.toggle() }) {
                Image(systemName: autoScroll ? "arrow.down.to.line.compact" : "arrow.down.to.line")
                    .font(.system(size: 11))
                    .foregroundColor(autoScroll ? .white.opacity(0.7) : .white.opacity(0.25))
            }
            .buttonStyle(.plain)
            .help("Auto-scroll")

            // Clear
            Button(action: { logger.clear() }) {
                Image(systemName: "trash")
                    .font(.system(size: 11))
                    .foregroundColor(.red.opacity(0.6))
            }
            .buttonStyle(.plain)
            .help("Clear console")

            // Copy all
            Button(action: copyLogsToClipboard) {
                Image(systemName: "doc.on.doc")
                    .font(.system(size: 11))
                    .foregroundColor(.white.opacity(0.35))
            }
            .buttonStyle(.plain)
            .help("Copy all logs")
        }
    }

    private var consoleEmptyState: some View {
        VStack(spacing: 12) {
            Spacer()
            Image(systemName: "terminal")
                .font(.system(size: 32))
                .foregroundColor(.white.opacity(0.1))
            Text("No log entries")
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(.white.opacity(0.25))
            Text(filterCategory != nil || filterLevel != nil || !searchText.isEmpty
                 ? "Try adjusting your filters"
                 : "Events will appear here as they occur")
                .font(.system(size: 11))
                .foregroundColor(.white.opacity(0.15))
            Spacer()
        }
    }

    private func logEntryRow(_ entry: LogEntry) -> some View {
        HStack(alignment: .top, spacing: 0) {
            if showTimestamps {
                Text(entry.timeString)
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .foregroundColor(.white.opacity(0.2))
                    .frame(width: 80, alignment: .leading)
            }

            Text(entry.level.rawValue.prefix(3).uppercased())
                .font(.system(size: 9, weight: .bold, design: .monospaced))
                .foregroundColor(colorForLevel(entry.level))
                .frame(width: 36, alignment: .leading)

            Text(entry.category.rawValue.prefix(4).uppercased())
                .font(.system(size: 9, weight: .medium, design: .monospaced))
                .foregroundColor(.white.opacity(0.25))
                .frame(width: 40, alignment: .leading)

            Text(entry.message)
                .font(.system(size: 11, design: .monospaced))
                .foregroundColor(entry.level == .error ? .red.opacity(0.8) : .white.opacity(0.65))
                .frame(maxWidth: .infinity, alignment: .leading)
                .lineLimit(3)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 3)
        .background(
            entry.level == .error ? Color.red.opacity(0.04) :
            entry.level == .warning ? Color.orange.opacity(0.02) :
            Color.clear
        )
    }

    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    // MARK: - NETWORK TAB
    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

    private var networkTabContent: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(spacing: 16) {
                networkStatusCards
                latencyBreakdown
                networkLogSection
            }
            .padding(.horizontal, 28)
            .padding(.top, 4)
            .padding(.bottom, 28)
        }
    }

    private var networkStatusCards: some View {
        HStack(spacing: 12) {
            statusCard(
                icon: "wifi",
                label: "WebSocket",
                value: logger.webSocketStatus,
                color: logger.webSocketStatus == "Connected" ? .green.opacity(0.6) : .orange.opacity(0.6)
            )
            statusCard(
                icon: "clock",
                label: "Avg Latency",
                value: logger.latencyDescription,
                color: latencyColor
            )
            statusCard(
                icon: "arrow.up.arrow.down",
                label: "Endpoints",
                value: "\(logger.networkLatencies.count)",
                color: .white.opacity(0.5)
            )
            statusCard(
                icon: "exclamationmark.triangle",
                label: "Errors",
                value: "\(networkErrorCount)",
                color: networkErrorCount > 0 ? .red.opacity(0.7) : .green.opacity(0.5)
            )
        }
    }

    private func statusCard(icon: String, label: String, value: String, color: Color) -> some View {
        VStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 14))
                .foregroundColor(color)
            Text(value)
                .font(.system(size: 13, weight: .semibold, design: .monospaced))
                .foregroundColor(.white.opacity(0.85))
                .lineLimit(1)
            Text(label)
                .font(.system(size: 9))
                .foregroundColor(.white.opacity(0.3))
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 14)
        .background(Color.white.opacity(0.03))
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private var latencyBreakdown: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionLabel("ENDPOINT LATENCY")

            if logger.networkLatencies.isEmpty {
                HStack {
                    Spacer()
                    Text("No network requests recorded")
                        .font(.system(size: 11))
                        .foregroundColor(.white.opacity(0.2))
                    Spacer()
                }
                .padding(.vertical, 16)
            } else {
                ForEach(sortedLatencies, id: \.key) { endpoint, latency in
                    HStack(spacing: 10) {
                        GeometryReader { geo in
                            let maxLatency = maxRecordedLatency
                            let fraction = maxLatency > 0 ? min(latency / maxLatency, 1.0) : 0
                            RoundedRectangle(cornerRadius: 2, style: .continuous)
                                .fill(latencyBarColor(latency))
                                .frame(width: geo.size.width * fraction)
                        }
                        .frame(height: 4)
                        .frame(maxWidth: 120)

                        Text(shortEndpoint(endpoint))
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundColor(.white.opacity(0.5))
                            .lineLimit(1)
                            .frame(maxWidth: .infinity, alignment: .leading)

                        Text(String(format: "%.0fms", latency * 1000))
                            .font(.system(size: 10, weight: .semibold, design: .monospaced))
                            .foregroundColor(latencyBarColor(latency))
                    }
                    .padding(.vertical, 2)
                }
            }
        }
        .padding(16)
        .background(Color.white.opacity(0.03))
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private var networkLogSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                sectionLabel("NETWORK LOG")
                Spacer()
                Text("\(networkEntries.count)")
                    .font(.system(size: 9, weight: .semibold, design: .monospaced))
                    .foregroundColor(.white.opacity(0.25))
            }

            if networkEntries.isEmpty {
                HStack {
                    Spacer()
                    Text("No network events")
                        .font(.system(size: 11))
                        .foregroundColor(.white.opacity(0.2))
                    Spacer()
                }
                .padding(.vertical, 12)
            } else {
                ForEach(networkEntries.suffix(30)) { entry in
                    HStack(spacing: 8) {
                        Text(entry.timeString)
                            .font(.system(size: 9, design: .monospaced))
                            .foregroundColor(.white.opacity(0.2))
                            .frame(width: 70, alignment: .leading)
                        Circle()
                            .fill(colorForLevel(entry.level))
                            .frame(width: 5, height: 5)
                        Text(entry.message)
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundColor(.white.opacity(0.55))
                            .lineLimit(1)
                    }
                    .padding(.vertical, 1)
                }
            }
        }
        .padding(16)
        .background(Color.white.opacity(0.03))
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    // MARK: - SYSTEM TAB
    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

    private var systemTabContent: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(spacing: 16) {
                appInfoSection
                memorySection
                logStatsSection
                actionsSection
            }
            .padding(.horizontal, 28)
            .padding(.top, 4)
            .padding(.bottom, 28)
        }
    }

    private var appInfoSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionLabel("APP INFO")

            let infoPairs: [(String, String)] = [
                ("Version", Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "—"),
                ("Build", Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "—"),
                ("Bundle ID", Bundle.main.bundleIdentifier ?? "—"),
                ("Platform", "macOS \(ProcessInfo.processInfo.operatingSystemVersionString)"),
                ("Architecture", architectureString),
                ("Process ID", "\(ProcessInfo.processInfo.processIdentifier)"),
            ]

            ForEach(infoPairs, id: \.0) { label, value in
                HStack {
                    Text(label)
                        .font(.system(size: 11))
                        .foregroundColor(.white.opacity(0.4))
                    Spacer()
                    Text(value)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundColor(.white.opacity(0.65))
                        .lineLimit(1)
                }
            }
        }
        .padding(16)
        .background(Color.white.opacity(0.03))
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private var memorySection: some View {
        let memPairs = memoryPairs
        return VStack(alignment: .leading, spacing: 10) {
            sectionLabel("MEMORY")

            ForEach(memPairs, id: \.0) { label, value in
                HStack {
                    Text(label)
                        .font(.system(size: 11))
                        .foregroundColor(.white.opacity(0.4))
                    Spacer()
                    Text(value)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundColor(.white.opacity(0.65))
                }
            }
        }
        .padding(16)
        .background(Color.white.opacity(0.03))
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private var logStatsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionLabel("LOG STATISTICS")

            let total = logger.entries.count
            let debugCount = logger.entries.filter { $0.level == .debug }.count
            let infoCount = logger.entries.filter { $0.level == .info }.count
            let warnCount = logger.entries.filter { $0.level == .warning }.count
            let errCount = logger.entries.filter { $0.level == .error }.count

            HStack(spacing: 16) {
                logStatPill("Total", count: total, color: .white.opacity(0.5))
                logStatPill("Debug", count: debugCount, color: .white.opacity(0.3))
                logStatPill("Info", count: infoCount, color: .cyan.opacity(0.6))
                logStatPill("Warn", count: warnCount, color: .orange.opacity(0.6))
                logStatPill("Error", count: errCount, color: .red.opacity(0.7))
                Spacer()
            }

            if total > 0 {
                GeometryReader { geo in
                    HStack(spacing: 1) {
                        if debugCount > 0 {
                            RoundedRectangle(cornerRadius: 2)
                                .fill(Color.white.opacity(0.15))
                                .frame(width: max(2, geo.size.width * CGFloat(debugCount) / CGFloat(total)))
                        }
                        if infoCount > 0 {
                            RoundedRectangle(cornerRadius: 2)
                                .fill(Color.cyan.opacity(0.4))
                                .frame(width: max(2, geo.size.width * CGFloat(infoCount) / CGFloat(total)))
                        }
                        if warnCount > 0 {
                            RoundedRectangle(cornerRadius: 2)
                                .fill(Color.orange.opacity(0.5))
                                .frame(width: max(2, geo.size.width * CGFloat(warnCount) / CGFloat(total)))
                        }
                        if errCount > 0 {
                            RoundedRectangle(cornerRadius: 2)
                                .fill(Color.red.opacity(0.6))
                                .frame(width: max(2, geo.size.width * CGFloat(errCount) / CGFloat(total)))
                        }
                    }
                }
                .frame(height: 6)
                .clipShape(RoundedRectangle(cornerRadius: 3))
            }
        }
        .padding(16)
        .background(Color.white.opacity(0.03))
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private func logStatPill(_ label: String, count: Int, color: Color) -> some View {
        VStack(spacing: 2) {
            Text("\(count)")
                .font(.system(size: 14, weight: .semibold, design: .monospaced))
                .foregroundColor(color)
            Text(label)
                .font(.system(size: 9))
                .foregroundColor(.white.opacity(0.3))
        }
    }

    private var actionsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionLabel("ACTIONS")

            HStack(spacing: 10) {
                actionButton(icon: "doc.on.doc", label: "Copy Logs") {
                    copyLogsToClipboard()
                }
                actionButton(icon: "trash", label: "Clear All") {
                    logger.clear()
                }
                actionButton(icon: "arrow.clockwise", label: "Add Test Entry") {
                    logger.log("Test entry at \(Date().formatted(date: .omitted, time: .standard))", level: .debug, category: .general)
                }
            }
        }
        .padding(16)
        .background(Color.white.opacity(0.03))
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private func actionButton(icon: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 11))
                Text(label)
                    .font(.system(size: 10, weight: .semibold))
            }
            .foregroundColor(.white.opacity(0.5))
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(Color.white.opacity(0.05))
            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.06), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }

    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    // MARK: - Computed Properties
    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

    private var memoryPairs: [(String, String)] {
        let memory = ProcessInfo.processInfo.physicalMemory
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useGB, .useMB]
        formatter.countStyle = .memory
        return [
            ("Physical RAM", formatter.string(fromByteCount: Int64(memory))),
            ("Active CPUs", "\(ProcessInfo.processInfo.activeProcessorCount)"),
            ("Uptime", uptimeString),
            ("Thermal State", thermalStateString),
        ]
    }

    private var filteredEntries: [LogEntry] {
        var result = logger.entries
        if let cat = filterCategory {
            result = result.filter { $0.category == cat }
        }
        if let level = filterLevel {
            result = result.filter { $0.level == level }
        }
        if !searchText.isEmpty {
            let query = searchText.lowercased()
            result = result.filter { $0.message.lowercased().contains(query) }
        }
        return result
    }

    private var networkEntries: [LogEntry] {
        logger.entries.filter { $0.category == .network }.reversed()
    }

    private var networkErrorCount: Int {
        logger.entries.filter { $0.category == .network && $0.level == .error }.count
    }

    private var sortedLatencies: [(key: String, value: TimeInterval)] {
        logger.networkLatencies.sorted { $0.value > $1.value }
    }

    private var maxRecordedLatency: TimeInterval {
        logger.networkLatencies.values.max() ?? 1.0
    }

    private var latencyColor: Color {
        guard let avg = logger.averageLatency else { return .white.opacity(0.3) }
        if avg < 0.2 { return .green.opacity(0.6) }
        if avg < 0.5 { return .orange.opacity(0.6) }
        return .red.opacity(0.7)
    }

    private var architectureString: String {
        #if arch(arm64)
        return "Apple Silicon (arm64)"
        #elseif arch(x86_64)
        return "Intel (x86_64)"
        #else
        return "Unknown"
        #endif
    }

    private var uptimeString: String {
        let uptime = ProcessInfo.processInfo.systemUptime
        let hours = Int(uptime) / 3600
        let minutes = (Int(uptime) % 3600) / 60
        return "\(hours)h \(minutes)m"
    }

    private var thermalStateString: String {
        switch ProcessInfo.processInfo.thermalState {
        case .nominal: return "Nominal"
        case .fair: return "Fair"
        case .serious: return "Serious"
        case .critical: return "Critical"
        @unknown default: return "Unknown"
        }
    }

    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    // MARK: - Helpers
    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

    private func colorForLevel(_ level: LogLevel) -> Color {
        switch level {
        case .debug: return .white.opacity(0.25)
        case .info: return .cyan.opacity(0.6)
        case .warning: return .orange.opacity(0.6)
        case .error: return .red.opacity(0.7)
        }
    }

    private func latencyBarColor(_ latency: TimeInterval) -> Color {
        if latency < 0.2 { return .green.opacity(0.6) }
        if latency < 0.5 { return .orange.opacity(0.6) }
        return .red.opacity(0.7)
    }

    private func shortEndpoint(_ endpoint: String) -> String {
        if let url = URL(string: endpoint) {
            return url.host ?? endpoint
        }
        if endpoint.count > 40 {
            return String(endpoint.prefix(37)) + "..."
        }
        return endpoint
    }

    private func copyLogsToClipboard() {
        let text = filteredEntries.map { entry in
            "[\(entry.timeString)] [\(entry.level.rawValue.uppercased())] [\(entry.category.rawValue)] \(entry.message)"
        }.joined(separator: "\n")

        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text.isEmpty ? "(no log entries)" : text, forType: .string)
    }

    private func sectionLabel(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 10, weight: .semibold, design: .monospaced))
            .tracking(1)
            .foregroundColor(.white.opacity(0.3))
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
