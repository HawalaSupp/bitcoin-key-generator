import SwiftUI

// MARK: - Transaction Notes View
/// Manage notes, tags, and categories for transactions
struct TransactionNotesView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var isLoading = false
    @State private var error: String?
    @State private var appearAnimation = false
    
    // Search and filter
    @State private var searchQuery = ""
    @State private var selectedCategory: HawalaBridge.NoteCategory?
    @State private var selectedChain: HawalaChain?
    @State private var pinnedOnly = false
    @State private var selectedTags: Set<String> = []
    
    // Notes data
    @State private var notes: [HawalaBridge.TransactionNote] = []
    @State private var totalCount = 0
    @State private var hasMore = false
    
    // Add note sheet
    @State private var showAddNoteSheet = false
    @State private var newNoteTxHash = ""
    @State private var newNoteContent = ""
    @State private var newNoteCategory: HawalaBridge.NoteCategory = .other
    @State private var newNoteTags = ""
    @State private var newNoteChain: HawalaChain = .ethereum
    
    // Export
    @State private var showExportSheet = false
    @State private var exportFormat = "json"
    
    private let allCategories: [HawalaBridge.NoteCategory] = [
        .income, .expense, .transfer, .swap,
        .airdrop, .stake, .unstake, .gas, .fee, .other
    ]
    
    private let chains: [HawalaChain] = [
        .bitcoin, .ethereum, .solana, .bnb, .litecoin
    ]
    
    var body: some View {
        ZStack {
            HawalaTheme.Colors.background
                .ignoresSafeArea()
            
            VStack(spacing: 0) {
                // Header
                headerView
                
                // Search and filters
                searchAndFiltersSection
                
                Divider()
                    .background(HawalaTheme.Colors.divider)
                
                // Content
                if isLoading && notes.isEmpty {
                    loadingView
                } else if notes.isEmpty {
                    emptyStateView
                } else {
                    notesListView
                }
            }
            
            // FAB for adding note
            VStack {
                Spacer()
                HStack {
                    Spacer()
                    addNoteButton
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
        .frame(minWidth: 600, idealWidth: 700, minHeight: 500, idealHeight: 650)
        .onAppear {
            withAnimation(HawalaTheme.Animation.spring) {
                appearAnimation = true
            }
            Task { await searchNotes() }
        }
        .sheet(isPresented: $showAddNoteSheet) {
            addNoteSheet
        }
        .sheet(isPresented: $showExportSheet) {
            exportSheet
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
                Text("Transaction Notes")
                    .font(HawalaTheme.Typography.h3)
                    .foregroundColor(HawalaTheme.Colors.textPrimary)
                
                Text("\(totalCount) notes")
                    .font(HawalaTheme.Typography.caption)
                    .foregroundColor(HawalaTheme.Colors.textSecondary)
            }
            
            Spacer()
            
            // Export button
            Button(action: { showExportSheet = true }) {
                Image(systemName: "square.and.arrow.up")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(HawalaTheme.Colors.textSecondary)
                    .frame(width: 32, height: 32)
                    .background(HawalaTheme.Colors.backgroundTertiary)
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)
        }
        .padding()
    }
    
    // MARK: - Search and Filters
    
    private var searchAndFiltersSection: some View {
        VStack(spacing: HawalaTheme.Spacing.sm) {
            // Search field
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(HawalaTheme.Colors.textTertiary)
                
                TextField("Search notes...", text: $searchQuery)
                    .textFieldStyle(.plain)
                    .font(HawalaTheme.Typography.body)
                    .onSubmit {
                        Task { await searchNotes() }
                    }
                
                if !searchQuery.isEmpty {
                    Button(action: {
                        searchQuery = ""
                        Task { await searchNotes() }
                    }) {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(HawalaTheme.Colors.textTertiary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(HawalaTheme.Spacing.md)
            .background(HawalaTheme.Colors.backgroundTertiary)
            .clipShape(RoundedRectangle(cornerRadius: HawalaTheme.Radius.md))
            
            // Filter chips
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: HawalaTheme.Spacing.sm) {
                    // Pinned filter
                    filterChip(
                        label: "Pinned",
                        icon: "pin.fill",
                        isSelected: pinnedOnly,
                        action: {
                            pinnedOnly.toggle()
                            Task { await searchNotes() }
                        }
                    )
                    
                    Divider()
                        .frame(height: 20)
                    
                    // Category filters
                    ForEach(allCategories, id: \.rawValue) { category in
                        filterChip(
                            label: category.rawValue.capitalized,
                            icon: categoryIcon(category),
                            isSelected: selectedCategory == category,
                            action: {
                                selectedCategory = selectedCategory == category ? nil : category
                                Task { await searchNotes() }
                            }
                        )
                    }
                }
                .padding(.horizontal, HawalaTheme.Spacing.lg)
            }
        }
        .padding(.vertical, HawalaTheme.Spacing.sm)
    }
    
    private func filterChip(label: String, icon: String, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 10))
                Text(label)
                    .font(HawalaTheme.Typography.label)
            }
            .foregroundColor(isSelected ? .white : HawalaTheme.Colors.textSecondary)
            .padding(.horizontal, HawalaTheme.Spacing.sm)
            .padding(.vertical, HawalaTheme.Spacing.xs)
            .background(isSelected ? HawalaTheme.Colors.accent : HawalaTheme.Colors.backgroundSecondary)
            .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }
    
    private func categoryIcon(_ category: HawalaBridge.NoteCategory) -> String {
        switch category {
        case .income: return "arrow.down.circle"
        case .expense: return "arrow.up.circle"
        case .transfer: return "arrow.left.arrow.right"
        case .swap: return "arrow.triangle.2.circlepath"
        case .airdrop: return "gift"
        case .stake: return "lock"
        case .unstake: return "lock.open"
        case .gas: return "fuelpump"
        case .fee: return "percent"
        case .collectible: return "square.grid.2x2"
        case .other: return "ellipsis.circle"
        }
    }
    
    // MARK: - Notes List
    
    private var notesListView: some View {
        ScrollView(showsIndicators: false) {
            LazyVStack(spacing: HawalaTheme.Spacing.sm) {
                ForEach(notes, id: \.txHash) { note in
                    noteCard(note: note)
                }
                
                if hasMore {
                    Button(action: { /* Load more */ }) {
                        Text("Load More")
                            .font(HawalaTheme.Typography.captionBold)
                            .foregroundColor(HawalaTheme.Colors.accent)
                    }
                    .buttonStyle(.plain)
                    .padding()
                }
            }
            .padding(.horizontal, HawalaTheme.Spacing.lg)
            .padding(.vertical, HawalaTheme.Spacing.md)
            .padding(.bottom, 80) // Space for FAB
        }
    }
    
    private func noteCard(note: HawalaBridge.TransactionNote) -> some View {
        VStack(alignment: .leading, spacing: HawalaTheme.Spacing.sm) {
            // Header row
            HStack {
                // Chain badge
                Text(note.chain.uppercased())
                    .font(HawalaTheme.Typography.label)
                    .foregroundColor(chainColor(note.chain))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(chainColor(note.chain).opacity(0.15))
                    .clipShape(Capsule())
                
                // Category
                if let category = note.category {
                    HStack(spacing: 4) {
                        Image(systemName: categoryIcon(category))
                            .font(.system(size: 10))
                        Text(category.rawValue.capitalized)
                            .font(HawalaTheme.Typography.label)
                    }
                    .foregroundColor(HawalaTheme.Colors.textSecondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(HawalaTheme.Colors.backgroundTertiary)
                    .clipShape(Capsule())
                }
                
                Spacer()
                
                // Pinned indicator
                if note.isPinned {
                    Image(systemName: "pin.fill")
                        .font(.system(size: 12))
                        .foregroundColor(HawalaTheme.Colors.warning)
                }
                
                // Timestamp
                Text(formatTimestamp(note.createdAt))
                    .font(HawalaTheme.Typography.caption)
                    .foregroundColor(HawalaTheme.Colors.textTertiary)
            }
            
            // Transaction hash
            Text(note.txHash)
                .font(HawalaTheme.Typography.monoSmall)
                .foregroundColor(HawalaTheme.Colors.textSecondary)
                .lineLimit(1)
                .truncationMode(.middle)
            
            // Note content
            Text(note.content)
                .font(HawalaTheme.Typography.body)
                .foregroundColor(HawalaTheme.Colors.textPrimary)
                .lineLimit(3)
            
            // Tags
            if !note.tags.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 4) {
                        ForEach(note.tags, id: \.self) { tag in
                            Text("#\(tag)")
                                .font(HawalaTheme.Typography.caption)
                                .foregroundColor(HawalaTheme.Colors.accent)
                        }
                    }
                }
            }
        }
        .padding(HawalaTheme.Spacing.md)
        .background(HawalaTheme.Colors.backgroundSecondary)
        .clipShape(RoundedRectangle(cornerRadius: HawalaTheme.Radius.md))
        .overlay(
            RoundedRectangle(cornerRadius: HawalaTheme.Radius.md)
                .strokeBorder(
                    note.isPinned ? HawalaTheme.Colors.warning.opacity(0.3) : HawalaTheme.Colors.border,
                    lineWidth: 1
                )
        )
    }
    
    private func chainColor(_ chain: String) -> Color {
        switch chain.lowercased() {
        case "bitcoin": return HawalaTheme.Colors.bitcoin
        case "ethereum": return HawalaTheme.Colors.ethereum
        case "solana": return HawalaTheme.Colors.solana
        case "bnb": return HawalaTheme.Colors.bnb
        case "litecoin": return HawalaTheme.Colors.litecoin
        default: return HawalaTheme.Colors.textSecondary
        }
    }
    
    private func formatTimestamp(_ timestamp: UInt64) -> String {
        let date = Date(timeIntervalSince1970: TimeInterval(timestamp))
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: date, relativeTo: Date())
    }
    
    // MARK: - Empty State
    
    private var emptyStateView: some View {
        VStack(spacing: HawalaTheme.Spacing.lg) {
            Spacer()
            
            Image(systemName: "note.text")
                .font(.system(size: 48))
                .foregroundColor(HawalaTheme.Colors.textTertiary)
            
            VStack(spacing: HawalaTheme.Spacing.sm) {
                Text("No Notes Yet")
                    .font(HawalaTheme.Typography.h3)
                    .foregroundColor(HawalaTheme.Colors.textPrimary)
                
                Text("Add notes to your transactions to keep track of what they were for")
                    .font(HawalaTheme.Typography.body)
                    .foregroundColor(HawalaTheme.Colors.textSecondary)
                    .multilineTextAlignment(.center)
            }
            
            Button(action: { showAddNoteSheet = true }) {
                HStack {
                    Image(systemName: "plus")
                    Text("Add Your First Note")
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
            Text(LoadingCopy.notes)
                .font(HawalaTheme.Typography.caption)
                .foregroundColor(HawalaTheme.Colors.textSecondary)
                .padding(.top)
            Spacer()
        }
    }
    
    // MARK: - Add Note Button
    
    private var addNoteButton: some View {
        Button(action: { showAddNoteSheet = true }) {
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
    
    // MARK: - Add Note Sheet
    
    private var addNoteSheet: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Button("Cancel") { showAddNoteSheet = false }
                    .buttonStyle(.plain)
                    .foregroundColor(HawalaTheme.Colors.textSecondary)
                
                Spacer()
                
                Text("Add Note")
                    .font(HawalaTheme.Typography.h4)
                
                Spacer()
                
                Button("Save") {
                    Task { await addNote() }
                }
                .buttonStyle(.plain)
                .foregroundColor(HawalaTheme.Colors.accent)
                .disabled(newNoteTxHash.isEmpty || newNoteContent.isEmpty)
            }
            .padding()
            
            Divider()
            
            ScrollView {
                VStack(spacing: HawalaTheme.Spacing.lg) {
                    // Chain selector
                    VStack(alignment: .leading, spacing: HawalaTheme.Spacing.xs) {
                        Text("CHAIN")
                            .font(HawalaTheme.Typography.label)
                            .foregroundColor(HawalaTheme.Colors.textTertiary)
                        
                        Picker("Chain", selection: $newNoteChain) {
                            ForEach(chains, id: \.rawValue) { chain in
                                Text(chain.rawValue.capitalized).tag(chain)
                            }
                        }
                        .pickerStyle(.segmented)
                    }
                    
                    // Transaction hash
                    VStack(alignment: .leading, spacing: HawalaTheme.Spacing.xs) {
                        Text("TRANSACTION HASH")
                            .font(HawalaTheme.Typography.label)
                            .foregroundColor(HawalaTheme.Colors.textTertiary)
                        
                        TextField("0x...", text: $newNoteTxHash)
                            .textFieldStyle(.plain)
                            .font(HawalaTheme.Typography.mono)
                            .padding(HawalaTheme.Spacing.md)
                            .background(HawalaTheme.Colors.backgroundTertiary)
                            .clipShape(RoundedRectangle(cornerRadius: HawalaTheme.Radius.md))
                    }
                    
                    // Category
                    VStack(alignment: .leading, spacing: HawalaTheme.Spacing.xs) {
                        Text("CATEGORY")
                            .font(HawalaTheme.Typography.label)
                            .foregroundColor(HawalaTheme.Colors.textTertiary)
                        
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: HawalaTheme.Spacing.sm) {
                                ForEach(allCategories, id: \.rawValue) { category in
                                    Button(action: { newNoteCategory = category }) {
                                        HStack(spacing: 4) {
                                            Image(systemName: categoryIcon(category))
                                                .font(.system(size: 12))
                                            Text(category.rawValue.capitalized)
                                                .font(HawalaTheme.Typography.captionBold)
                                        }
                                        .foregroundColor(newNoteCategory == category ? .white : HawalaTheme.Colors.textSecondary)
                                        .padding(.horizontal, HawalaTheme.Spacing.md)
                                        .padding(.vertical, HawalaTheme.Spacing.sm)
                                        .background(newNoteCategory == category ? HawalaTheme.Colors.accent : HawalaTheme.Colors.backgroundTertiary)
                                        .clipShape(Capsule())
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }
                    }
                    
                    // Note content
                    VStack(alignment: .leading, spacing: HawalaTheme.Spacing.xs) {
                        Text("NOTE")
                            .font(HawalaTheme.Typography.label)
                            .foregroundColor(HawalaTheme.Colors.textTertiary)
                        
                        TextEditor(text: $newNoteContent)
                            .font(HawalaTheme.Typography.body)
                            .scrollContentBackground(.hidden)
                            .padding(HawalaTheme.Spacing.md)
                            .frame(height: 120)
                            .background(HawalaTheme.Colors.backgroundTertiary)
                            .clipShape(RoundedRectangle(cornerRadius: HawalaTheme.Radius.md))
                    }
                    
                    // Tags
                    VStack(alignment: .leading, spacing: HawalaTheme.Spacing.xs) {
                        Text("TAGS (COMMA SEPARATED)")
                            .font(HawalaTheme.Typography.label)
                            .foregroundColor(HawalaTheme.Colors.textTertiary)
                        
                        TextField("salary, monthly, work", text: $newNoteTags)
                            .textFieldStyle(.plain)
                            .font(HawalaTheme.Typography.body)
                            .padding(HawalaTheme.Spacing.md)
                            .background(HawalaTheme.Colors.backgroundTertiary)
                            .clipShape(RoundedRectangle(cornerRadius: HawalaTheme.Radius.md))
                    }
                }
                .padding()
            }
        }
        .frame(width: 500, height: 550)
        .background(HawalaTheme.Colors.background)
    }
    
    // MARK: - Export Sheet
    
    private var exportSheet: some View {
        VStack(spacing: HawalaTheme.Spacing.lg) {
            Text("Export Notes")
                .font(HawalaTheme.Typography.h3)
            
            Picker("Format", selection: $exportFormat) {
                Text("JSON").tag("json")
                Text("CSV").tag("csv")
            }
            .pickerStyle(.segmented)
            
            Button(action: { Task { await exportNotes() } }) {
                Text("Export \(totalCount) Notes")
                    .font(HawalaTheme.Typography.captionBold)
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(HawalaTheme.Spacing.md)
                    .background(HawalaTheme.Colors.accent)
                    .clipShape(RoundedRectangle(cornerRadius: HawalaTheme.Radius.md))
            }
            .buttonStyle(.plain)
            
            Button("Cancel") { showExportSheet = false }
                .buttonStyle(.plain)
                .foregroundColor(HawalaTheme.Colors.textSecondary)
        }
        .padding(HawalaTheme.Spacing.xl)
        .frame(width: 300)
        .background(HawalaTheme.Colors.background)
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
    
    // MARK: - Data Operations
    
    private func searchNotes() async {
        isLoading = true
        error = nil
        
        do {
            let tags = selectedTags.isEmpty ? nil : Array(selectedTags)
            let result = try HawalaBridge.shared.searchNotes(
                query: searchQuery.isEmpty ? nil : searchQuery,
                chain: selectedChain,
                tags: tags,
                category: selectedCategory,
                pinnedOnly: pinnedOnly
            )
            
            notes = result.notes
            totalCount = result.totalCount
            hasMore = result.hasMore
        } catch {
            self.error = error.localizedDescription
        }
        
        isLoading = false
    }
    
    private func addNote() async {
        isLoading = true
        error = nil
        
        do {
            let tags = newNoteTags.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
            
            _ = try HawalaBridge.shared.addNote(
                txHash: newNoteTxHash,
                chain: newNoteChain,
                content: newNoteContent,
                tags: tags.isEmpty ? nil : tags,
                category: newNoteCategory
            )
            
            // Reset form
            newNoteTxHash = ""
            newNoteContent = ""
            newNoteTags = ""
            showAddNoteSheet = false
            
            // Refresh list
            await searchNotes()
        } catch {
            self.error = error.localizedDescription
        }
        
        isLoading = false
    }
    
    private func exportNotes() async {
        do {
            let data = try HawalaBridge.shared.exportNotes(format: exportFormat)
            // Would save to file or share
            print("Exported \(data.count) characters")
            showExportSheet = false
        } catch {
            self.error = error.localizedDescription
        }
    }
}

// MARK: - Preview

#if DEBUG
struct TransactionNotesView_Previews: PreviewProvider {
    static var previews: some View {
        TransactionNotesView()
            .preferredColorScheme(.dark)
    }
}
#endif
