import SwiftUI

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// MARK: – Transaction Notes Premium Overlay
// Matches the Bitcoin detail card aesthetic: monumental typography, strictly
// monochrome, mechanical interactions, expandable transaction ribbon.
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

struct TransactionNotesOverlay: View {
    @Binding var isPresented: Bool
    let transactions: [HawalaTransactionEntry]

    // ── State ──
    @State private var searchQuery: String = ""
    @State private var selectedTagFilter: String? = nil
    @State private var expandedTxId: String? = nil
    @State private var isSearchActive: Bool = false

    // ── Note editing ──
    @State private var editingNoteId: String? = nil
    @State private var noteTexts: [String: String] = [:]          // txHash → note
    @State private var txTags: [String: Set<String>] = [:]        // txHash → tags
    @State private var newTagText: String = ""

    // ── Tag management ──
    @State private var allTags: [String] = ["salary", "rent", "gift", "refund", "savings", "food", "travel", "business"]
    @State private var showTagManager: Bool = false

    // ── Data from bridge ──
    @State private var bridgeNotes: [HawalaBridge.TransactionNote] = []
    @State private var isLoading: Bool = true

    // ── Entrance animation ──
    @State private var contentOpacity: Double = 0
    @State private var cardScale: CGFloat = 0.92

    // ── Hover ──
    @State private var closeHovered: Bool = false
    @State private var searchIconHovered: Bool = false
    @State private var tagManagerHovered: Bool = false

    // ── Derived ──
    private var displayTransactions: [HawalaTransactionEntry] {
        var txs = transactions

        // Filter by search
        if !searchQuery.isEmpty {
            let q = searchQuery.lowercased()
            txs = txs.filter { tx in
                let noteMatch = (noteTexts[tx.id] ?? "").lowercased().contains(q)
                let tagMatch = (txTags[tx.id] ?? []).contains { $0.lowercased().contains(q) }
                let amountMatch = tx.amountDisplay.lowercased().contains(q)
                let assetMatch = tx.asset.lowercased().contains(q)
                let counterpartyMatch = (tx.counterparty ?? "").lowercased().contains(q)
                return noteMatch || tagMatch || amountMatch || assetMatch || counterpartyMatch
            }
        }

        // Filter by tag
        if let tag = selectedTagFilter {
            txs = txs.filter { txTags[$0.id]?.contains(tag) == true }
        }

        return txs
    }

    private var hasActiveFilter: Bool {
        !searchQuery.isEmpty || selectedTagFilter != nil
    }

    private var notedCount: Int {
        noteTexts.values.filter { !$0.isEmpty }.count
    }

    private var taggedCount: Int {
        txTags.values.filter { !$0.isEmpty }.count
    }

    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    // MARK: – Body
    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

    var body: some View {
        ZStack {
            // ── Dimmed backdrop ──
            Color.black.opacity(0.75)
                .ignoresSafeArea()
                .onTapGesture { dismissOverlay() }

            // ── Card ──
            VStack(spacing: 0) {
                headerSection
                searchBar
                tagFilterBar
                transactionRibbon
            }
            .frame(width: 460, height: 640)
            .background(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(Color(red: 0.10, green: 0.10, blue: 0.12))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .strokeBorder(
                        LinearGradient(
                            colors: [Color.white.opacity(0.10), Color.white.opacity(0.03)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 1
                    )
            )
            .shadow(color: Color.black.opacity(0.5), radius: 50, x: 0, y: 25)
            .scaleEffect(cardScale)

            // ── Tag manager overlay ──
            if showTagManager {
                tagManagerSheet
                    .transition(.opacity.combined(with: .move(edge: .bottom)))
                    .zIndex(2)
            }
        }
        .background(
            EscapeKeyHandler(isPresented: $isPresented, onEscape: dismissOverlay)
        )
        .onAppear {
            withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                cardScale = 1
                contentOpacity = 1
            }
            Task { await loadNotes() }
        }
    }

    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    // MARK: – Header
    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

    private var headerSection: some View {
        ZStack {
            // Centered title
            VStack(spacing: 4) {
                Text("Transaction Notes")
                    .font(.clashGroteskMedium(size: 20))
                    .foregroundColor(.white)

                if notedCount > 0 || taggedCount > 0 {
                    HStack(spacing: 8) {
                        if notedCount > 0 {
                            Text("\(notedCount) noted")
                                .font(.system(size: 11, weight: .medium))
                        }
                        if notedCount > 0 && taggedCount > 0 {
                            Text("·")
                        }
                        if taggedCount > 0 {
                            Text("\(taggedCount) tagged")
                                .font(.system(size: 11, weight: .medium))
                        }
                    }
                    .foregroundColor(.white.opacity(0.3))
                }
            }

            HStack {
                // Tag manager button
                Button(action: {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
                        showTagManager.toggle()
                    }
                }) {
                    Circle()
                        .fill(Color.white.opacity(tagManagerHovered ? 0.10 : (showTagManager ? 0.10 : 0.06)))
                        .frame(width: 32, height: 32)
                        .overlay(
                            Image(systemName: "tag")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundColor(.white.opacity(showTagManager ? 0.6 : 0.4))
                        )
                }
                .buttonStyle(.plain)
                .onHover { tagManagerHovered = $0 }

                Spacer()

                // Close
                Button(action: dismissOverlay) {
                    Circle()
                        .fill(Color.white.opacity(closeHovered ? 0.12 : 0.08))
                        .frame(width: 32, height: 32)
                        .overlay(
                            Image(systemName: "xmark")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundColor(.white.opacity(0.5))
                        )
                }
                .buttonStyle(.plain)
                .onHover { closeHovered = $0 }
            }
        }
        .padding(.horizontal, 24)
        .padding(.top, 24)
        .padding(.bottom, 8)
    }

    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    // MARK: – Search Bar
    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

    private var searchBar: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(.white.opacity(0.3))

            TextField("Search notes, tags, amounts…", text: $searchQuery)
                .textFieldStyle(.plain)
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(.white.opacity(0.75))

            if !searchQuery.isEmpty {
                Button(action: {
                    withAnimation(.easeOut(duration: 0.15)) { searchQuery = "" }
                }) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 12))
                        .foregroundColor(.white.opacity(0.25))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.white.opacity(0.04))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(Color.white.opacity(0.06), lineWidth: 0.5)
        )
        .padding(.horizontal, 24)
        .padding(.bottom, 8)
        .opacity(contentOpacity)
    }

    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    // MARK: – Tag Filter Bar
    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

    private var tagFilterBar: some View {
        let usedTags = collectUsedTags()
        guard !usedTags.isEmpty else { return AnyView(EmptyView()) }

        return AnyView(
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    // "All" pill
                    TagFilterPill(
                        label: "ALL",
                        isActive: selectedTagFilter == nil,
                        action: {
                            withAnimation(.easeOut(duration: 0.15)) {
                                selectedTagFilter = nil
                            }
                        }
                    )

                    ForEach(usedTags, id: \.self) { tag in
                        TagFilterPill(
                            label: tag.uppercased(),
                            isActive: selectedTagFilter == tag,
                            action: {
                                withAnimation(.easeOut(duration: 0.15)) {
                                    selectedTagFilter = selectedTagFilter == tag ? nil : tag
                                }
                            }
                        )
                    }
                }
                .padding(.horizontal, 24)
            }
            .padding(.bottom, 8)
            .opacity(contentOpacity)
        )
    }

    private func collectUsedTags() -> [String] {
        var tags = Set<String>()
        for set in txTags.values {
            tags.formUnion(set)
        }
        return tags.sorted()
    }

    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    // MARK: – Transaction Ribbon
    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

    private var transactionRibbon: some View {
        Group {
            if transactions.isEmpty && !isLoading {
                emptyState
            } else {
                ScrollView(.vertical, showsIndicators: false) {
                    LazyVStack(spacing: 1) {
                        let txs = displayTransactions
                        ForEach(Array(txs.enumerated()), id: \.element.id) { index, tx in
                            let isExpanded = expandedTxId == tx.id
                            let dimmed = hasActiveFilter && !displayTransactions.contains(where: { $0.id == tx.id })

                            TransactionRibbonSegment(
                                transaction: tx,
                                isExpanded: isExpanded,
                                noteText: Binding(
                                    get: { noteTexts[tx.id] ?? "" },
                                    set: { noteTexts[tx.id] = $0 }
                                ),
                                tags: Binding(
                                    get: { txTags[tx.id] ?? [] },
                                    set: { txTags[tx.id] = $0 }
                                ),
                                allTags: allTags,
                                onToggle: {
                                    withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
                                        expandedTxId = isExpanded ? nil : tx.id
                                    }
                                },
                                onSaveNote: { saveNote(for: tx) }
                            )
                            .opacity(dimmed ? 0.2 : 1)
                        }
                    }
                    .padding(.horizontal, 24)
                    .padding(.top, 4)
                    .padding(.bottom, 24)
                }
            }
        }
        .opacity(contentOpacity)
    }

    // ── Empty state ──
    private var emptyState: some View {
        VStack(spacing: 12) {
            Spacer()

            Image(systemName: "note.text")
                .font(.system(size: 32, weight: .thin))
                .foregroundColor(.white.opacity(0.12))

            Text("No Transactions")
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(.white.opacity(0.3))

            Text("Transaction history will appear here")
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(.white.opacity(0.15))

            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    // MARK: – Tag Manager Sheet
    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

    private var tagManagerSheet: some View {
        ZStack {
            // Backdrop
            Color.black.opacity(0.5)
                .ignoresSafeArea()
                .onTapGesture {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
                        showTagManager = false
                    }
                }

            VStack(spacing: 0) {
                // Header
                HStack {
                    Text("MANAGE TAGS")
                        .font(.system(size: 10, weight: .bold))
                        .tracking(2)
                        .foregroundColor(.white.opacity(0.4))

                    Spacer()

                    Button(action: {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
                            showTagManager = false
                        }
                    }) {
                        Image(systemName: "xmark")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundColor(.white.opacity(0.3))
                            .frame(width: 24, height: 24)
                            .background(Color.white.opacity(0.06))
                            .clipShape(Circle())
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 20)
                .padding(.top, 20)
                .padding(.bottom, 12)

                // Add new tag
                HStack(spacing: 8) {
                    TextField("New tag name", text: $newTagText)
                        .textFieldStyle(.plain)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(.white.opacity(0.7))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .fill(Color.white.opacity(0.04))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .strokeBorder(Color.white.opacity(0.06), lineWidth: 0.5)
                        )
                        .onSubmit { addCustomTag() }

                    Button(action: addCustomTag) {
                        Image(systemName: "plus")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(.white.opacity(0.4))
                            .frame(width: 32, height: 32)
                            .background(Color.white.opacity(0.06))
                            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .disabled(newTagText.trimmingCharacters(in: .whitespaces).isEmpty)
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 12)

                // Tag list
                ScrollView(.vertical, showsIndicators: false) {
                    VStack(spacing: 2) {
                        ForEach(allTags, id: \.self) { tag in
                            TagManagerRow(
                                tag: tag,
                                usageCount: tagUsageCount(tag),
                                onDelete: { removeTag(tag) }
                            )
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.bottom, 16)
                }
            }
            .frame(width: 320, height: 380)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Color(white: 0.12, opacity: 0.98))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.08), lineWidth: 0.5)
            )
            .shadow(color: Color.black.opacity(0.6), radius: 30, x: 0, y: 15)
        }
    }

    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    // MARK: – Actions
    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

    private func loadNotes() async {
        isLoading = true
        do {
            let result = try HawalaBridge.shared.searchNotes(
                query: nil,
                chain: nil,
                tags: nil,
                category: nil,
                pinnedOnly: false,
                limit: 100,
                offset: 0
            )
            // Merge bridge notes into local state
            for note in result.notes {
                noteTexts[note.txHash] = note.content
                txTags[note.txHash] = Set(note.tags)
            }
            bridgeNotes = result.notes
        } catch {
            // Graceful — local state still works
        }
        withAnimation { isLoading = false }
    }

    private func saveNote(for tx: HawalaTransactionEntry) {
        let content = noteTexts[tx.id] ?? ""
        let tags = Array(txTags[tx.id] ?? [])
        let chainRaw = tx.chainId ?? "bitcoin"
        let chain = HawalaChain(rawValue: chainRaw) ?? .bitcoin

        Task {
            _ = try? HawalaBridge.shared.addNote(
                txHash: tx.id,
                chain: chain,
                content: content,
                tags: tags,
                category: nil
            )
        }
    }

    private func addCustomTag() {
        let tag = newTagText.trimmingCharacters(in: .whitespaces).lowercased()
        guard !tag.isEmpty, !allTags.contains(tag) else { return }
        withAnimation(.spring(response: 0.25, dampingFraction: 0.85)) {
            allTags.append(tag)
        }
        newTagText = ""
    }

    private func removeTag(_ tag: String) {
        withAnimation(.spring(response: 0.25, dampingFraction: 0.85)) {
            allTags.removeAll { $0 == tag }
            // Also remove from all transactions
            for key in txTags.keys {
                txTags[key]?.remove(tag)
            }
            if selectedTagFilter == tag {
                selectedTagFilter = nil
            }
        }
    }

    private func tagUsageCount(_ tag: String) -> Int {
        txTags.values.filter { $0.contains(tag) }.count
    }

    private func dismissOverlay() {
        withAnimation(.spring(response: 0.25, dampingFraction: 0.9)) {
            cardScale = 0.95
            contentOpacity = 0
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            isPresented = false
        }
    }
}

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// MARK: – Tag Filter Pill
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

private struct TagFilterPill: View {
    let label: String
    let isActive: Bool
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            Text(label)
                .font(.system(size: 10, weight: isActive ? .bold : .medium))
                .tracking(1)
                .foregroundColor(.white.opacity(isActive ? 0.7 : 0.3))
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(
                    Capsule()
                        .fill(Color.white.opacity(isActive ? 0.10 : (isHovered ? 0.04 : 0)))
                )
                .overlay(
                    Capsule()
                        .strokeBorder(Color.white.opacity(isActive ? 0.12 : 0.04), lineWidth: 0.5)
                )
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
    }
}

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// MARK: – Transaction Ribbon Segment
// Each segment is a horizontal band that expands to reveal note + tag fields.
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

private struct TransactionRibbonSegment: View {
    let transaction: HawalaTransactionEntry
    let isExpanded: Bool
    @Binding var noteText: String
    @Binding var tags: Set<String>
    let allTags: [String]
    let onToggle: () -> Void
    let onSaveNote: () -> Void

    @State private var isHovered: Bool = false
    @State private var noteFieldFocused: Bool = false

    // Direction arrow
    private var directionIcon: String {
        switch transaction.type.lowercased() {
        case "send":    return "arrow.up.right"
        case "receive": return "arrow.down.left"
        case "swap":    return "arrow.triangle.2.circlepath"
        default:        return "arrow.right"
        }
    }

    private var hasNote: Bool { !noteText.isEmpty }
    private var hasTagsAttached: Bool { !tags.isEmpty }

    private var directionOpacity: Double {
        isExpanded ? 0.10 : 0.05
    }
    private var directionIconOpacity: Double {
        isExpanded ? 0.6 : 0.35
    }
    private var statusDotOpacity: Double {
        if transaction.status == "Confirmed" { return 0.25 }
        if transaction.status == "Pending" { return 0.15 }
        return 0.08
    }
    private var bgOpacity: Double {
        if isExpanded { return 0.05 }
        if isHovered { return 0.03 }
        return 0.015
    }
    private var borderOpacity: Double {
        isExpanded ? 0.08 : 0
    }
    private var chevronRotation: Double {
        isExpanded ? 180 : 0
    }

    var body: some View {
        VStack(spacing: 0) {
            collapsedRow
            if isExpanded {
                expandedSection
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.white.opacity(bgOpacity))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(Color.white.opacity(borderOpacity), lineWidth: 0.5)
        )
        .onHover { isHovered = $0 }
    }

    // MARK: - Collapsed Row
    private var collapsedRow: some View {
        HStack(spacing: 12) {
            directionIndicator
            txInfoColumn
            Spacer()
            statusChevron
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
        .contentShape(Rectangle())
        .onTapGesture { onToggle() }
    }

    private var directionIndicator: some View {
        ZStack {
            Circle()
                .fill(Color.white.opacity(directionOpacity))
                .frame(width: 32, height: 32)
            Image(systemName: directionIcon)
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(.white.opacity(directionIconOpacity))
        }
    }

    private var txInfoColumn: some View {
        VStack(alignment: .leading, spacing: 3) {
            amountRow
            detailRow
        }
    }

    private var amountRow: some View {
        HStack(spacing: 6) {
            Text(transaction.amountDisplay)
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(.white.opacity(0.85))
            if hasNote || hasTagsAttached {
                annotationIndicators
            }
        }
    }

    private var annotationIndicators: some View {
        HStack(spacing: 3) {
            if hasNote {
                Image(systemName: "note.text")
                    .font(.system(size: 8))
                    .foregroundColor(.white.opacity(0.2))
            }
            if hasTagsAttached {
                Image(systemName: "tag")
                    .font(.system(size: 8))
                    .foregroundColor(.white.opacity(0.2))
            }
        }
    }

    private var detailRow: some View {
        HStack(spacing: 6) {
            if let counterparty = transaction.counterparty, !counterparty.isEmpty {
                Text(shortenAddress(counterparty))
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .foregroundColor(.white.opacity(0.25))
            }
            Text(transaction.timestamp)
                .font(.system(size: 10, weight: .medium))
                .foregroundColor(.white.opacity(0.2))
        }
    }

    private var statusChevron: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(Color.white.opacity(statusDotOpacity))
                .frame(width: 5, height: 5)
            Image(systemName: "chevron.down")
                .font(.system(size: 10, weight: .medium))
                .foregroundColor(.white.opacity(0.2))
                .rotationEffect(.degrees(chevronRotation))
        }
    }

    // MARK: - Expanded Section
    private var expandedSection: some View {
        VStack(spacing: 0) {
            Rectangle()
                .fill(Color.white.opacity(0.04))
                .frame(height: 0.5)
                .padding(.horizontal, 14)

            noteInputArea
            tagArea
            saveRow
        }
        .transition(.asymmetric(
            insertion: .opacity.combined(with: .move(edge: .top)),
            removal: .opacity
        ))
    }

    private var noteInputArea: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("NOTE")
                .font(.system(size: 8, weight: .bold))
                .tracking(2)
                .foregroundColor(.white.opacity(0.2))

            ZStack(alignment: .topLeading) {
                if noteText.isEmpty {
                    Text("Add a private note…")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(.white.opacity(0.15))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 10)
                }

                TextEditor(text: $noteText)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(.white.opacity(0.7))
                    .scrollContentBackground(.hidden)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 6)
                    .frame(minHeight: 48, maxHeight: 80)
            }
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color.white.opacity(0.03))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.06), lineWidth: 0.5)
            )
        }
        .padding(.horizontal, 14)
        .padding(.top, 10)
    }

    private var tagArea: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("TAGS")
                .font(.system(size: 8, weight: .bold))
                .tracking(2)
                .foregroundColor(.white.opacity(0.2))

            attachedTagsFlow
        }
        .padding(.horizontal, 14)
        .padding(.top, 8)
    }

    private struct TagItem: Identifiable {
        let id: String
        let name: String
        let isAttached: Bool
    }

    private var attachedTagsFlow: some View {
        let sortedAttached = Array(tags).sorted()
        let available = allTags.filter { !tags.contains($0) }
        let items: [TagItem] = sortedAttached.map { TagItem(id: "a_\($0)", name: $0, isAttached: true) }
            + available.map { TagItem(id: "v_\($0)", name: $0, isAttached: false) }
        return FlowLayout(spacing: 6) {
            ForEach(items) { item in
                tagChip(for: item)
            }
        }
    }

    @ViewBuilder
    private func tagChip(for item: TagItem) -> some View {
        if item.isAttached {
            AttachedTag(label: item.name) {
                withAnimation(.spring(response: 0.2, dampingFraction: 0.8)) {
                    let _ = tags.remove(item.name)
                }
            }
        } else {
            AvailableTag(label: item.name) {
                withAnimation(.spring(response: 0.2, dampingFraction: 0.8)) {
                    let _ = tags.insert(item.name)
                }
            }
        }
    }

    private var saveRow: some View {
        HStack {
            Spacer()
            Button(action: onSaveNote) {
                Text("SAVE")
                    .font(.system(size: 9, weight: .bold))
                    .tracking(1.5)
                    .foregroundColor(.white.opacity(0.35))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(
                        RoundedRectangle(cornerRadius: 5, style: .continuous)
                            .fill(Color.white.opacity(0.05))
                    )
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 14)
        .padding(.top, 8)
        .padding(.bottom, 12)
    }

    private func shortenAddress(_ address: String) -> String {
        guard address.count > 12 else { return address }
        return "\(address.prefix(6))…\(address.suffix(4))"
    }
}

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// MARK: – Tag Shapes
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

/// An attached tag — shown as a filled capsule with "×" to remove
private struct AttachedTag: View {
    let label: String
    let onRemove: () -> Void

    @State private var isHovered = false

    var body: some View {
        HStack(spacing: 4) {
            // Geometric indicator
            RoundedRectangle(cornerRadius: 2, style: .continuous)
                .fill(Color.white.opacity(0.3))
                .frame(width: 6, height: 6)

            Text(label.uppercased())
                .font(.system(size: 9, weight: .bold))
                .tracking(1)
                .foregroundColor(.white.opacity(0.5))

            if isHovered {
                Image(systemName: "xmark")
                    .font(.system(size: 7, weight: .bold))
                    .foregroundColor(.white.opacity(0.3))
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(
            Capsule()
                .fill(Color.white.opacity(0.08))
        )
        .overlay(
            Capsule()
                .strokeBorder(Color.white.opacity(0.12), lineWidth: 0.5)
        )
        .onHover { isHovered = $0 }
        .onTapGesture { onRemove() }
    }
}

/// An available (unattached) tag — shown as an outlined capsule, click to attach
private struct AvailableTag: View {
    let label: String
    let onAttach: () -> Void

    @State private var isHovered = false

    var body: some View {
        HStack(spacing: 4) {
            Circle()
                .stroke(Color.white.opacity(0.15), lineWidth: 0.5)
                .frame(width: 6, height: 6)

            Text(label.uppercased())
                .font(.system(size: 9, weight: .medium))
                .tracking(1)
                .foregroundColor(.white.opacity(isHovered ? 0.35 : 0.2))
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(
            Capsule()
                .fill(Color.white.opacity(isHovered ? 0.04 : 0))
        )
        .overlay(
            Capsule()
                .strokeBorder(Color.white.opacity(isHovered ? 0.08 : 0.04), lineWidth: 0.5)
        )
        .onHover { isHovered = $0 }
        .onTapGesture { onAttach() }
    }
}

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// MARK: – Tag Manager Row
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

private struct TagManagerRow: View {
    let tag: String
    let usageCount: Int
    let onDelete: () -> Void

    @State private var isHovered = false

    var body: some View {
        HStack(spacing: 10) {
            RoundedRectangle(cornerRadius: 2, style: .continuous)
                .fill(Color.white.opacity(0.2))
                .frame(width: 8, height: 8)

            Text(tag.uppercased())
                .font(.system(size: 11, weight: .semibold))
                .tracking(1)
                .foregroundColor(.white.opacity(0.6))

            Spacer()

            if usageCount > 0 {
                Text("\(usageCount)")
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .foregroundColor(.white.opacity(0.2))
            }

            if isHovered {
                Button(action: onDelete) {
                    Image(systemName: "trash")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(.white.opacity(0.25))
                        .frame(width: 24, height: 24)
                        .background(Color.white.opacity(0.06))
                        .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
                }
                .buttonStyle(.plain)
                .transition(.opacity.combined(with: .scale(scale: 0.8)))
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(Color.white.opacity(isHovered ? 0.04 : 0.02))
        )
        .onHover { hovering in
            withAnimation(.easeOut(duration: 0.12)) { isHovered = hovering }
        }
        .contentShape(Rectangle())
    }
}

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// MARK: – Flow Layout (Wrapping Tags)
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

/// A simple wrapping layout for tags, compatible with macOS 13+
private struct FlowLayout: Layout {
    var spacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let result = arrangeSubviews(proposal: proposal, subviews: subviews)
        return result.size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = arrangeSubviews(proposal: proposal, subviews: subviews)
        for (index, position) in result.positions.enumerated() where index < subviews.count {
            subviews[index].place(at: CGPoint(x: bounds.minX + position.x, y: bounds.minY + position.y), proposal: .unspecified)
        }
    }

    private struct LayoutResult {
        var size: CGSize
        var positions: [CGPoint]
    }

    private func arrangeSubviews(proposal: ProposedViewSize, subviews: Subviews) -> LayoutResult {
        let maxWidth = proposal.width ?? .infinity
        var positions: [CGPoint] = []
        var currentX: CGFloat = 0
        var currentY: CGFloat = 0
        var rowHeight: CGFloat = 0
        var totalHeight: CGFloat = 0
        var totalWidth: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)

            if currentX + size.width > maxWidth && currentX > 0 {
                currentX = 0
                currentY += rowHeight + spacing
                rowHeight = 0
            }

            positions.append(CGPoint(x: currentX, y: currentY))
            rowHeight = max(rowHeight, size.height)
            currentX += size.width + spacing
            totalWidth = max(totalWidth, currentX)
            totalHeight = currentY + rowHeight
        }

        return LayoutResult(
            size: CGSize(width: totalWidth, height: totalHeight),
            positions: positions
        )
    }
}
