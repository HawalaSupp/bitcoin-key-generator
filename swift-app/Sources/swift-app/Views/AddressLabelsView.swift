import SwiftUI

// MARK: - Address Labels View
/// Main view for managing address labels and tags

struct AddressLabelsView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @ObservedObject private var labelManager = AddressLabelManager.shared
    
    @State private var searchText = ""
    @State private var selectedTab: Tab = .labels
    @State private var showAddLabel = false
    @State private var showAddTag = false
    @State private var editingLabel: AddressLabel?
    @State private var addressToLabel = ""
    
    enum Tab: String, CaseIterable {
        case labels = "Labels"
        case tags = "Tags"
        case favorites = "Favorites"
    }
    
    private var cardBackground: Color {
        colorScheme == .dark ? Color.white.opacity(0.05) : Color.black.opacity(0.03)
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            headerView
            
            Divider()
            
            // Tab bar
            tabBar
            
            Divider()
            
            // Content
            switch selectedTab {
            case .labels:
                labelsListView
            case .tags:
                tagsListView
            case .favorites:
                favoritesListView
            }
        }
        .background(HawalaTheme.Colors.background)
        .sheet(isPresented: $showAddLabel) {
            AddLabelSheet(initialAddress: addressToLabel, onSave: {
                showAddLabel = false
                addressToLabel = ""
            })
        }
        .sheet(isPresented: $showAddTag) {
            CreateTagView(manager: labelManager)
        }
        .sheet(item: $editingLabel) { label in
            AddressLabelEditorView(address: label.address, onSave: {
                editingLabel = nil
            })
        }
    }
    
    // MARK: - Header
    private var headerView: some View {
        HStack(spacing: HawalaTheme.Spacing.lg) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Address Labels")
                    .font(HawalaTheme.Typography.h2)
                    .foregroundColor(HawalaTheme.Colors.textPrimary)
                
                Text("\(labelManager.labels.count) labeled addresses, \(labelManager.tags.count) tags")
                    .font(HawalaTheme.Typography.bodySmall)
                    .foregroundColor(HawalaTheme.Colors.textSecondary)
            }
            
            Spacer()
            
            // Search
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(HawalaTheme.Colors.textTertiary)
                TextField("Search labels...", text: $searchText)
                    .textFieldStyle(.plain)
                    .frame(width: 150)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(cardBackground)
            .cornerRadius(8)
            
            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.title2)
                    .foregroundColor(HawalaTheme.Colors.textSecondary)
            }
            .buttonStyle(.plain)
        }
        .padding(HawalaTheme.Spacing.xl)
    }
    
    // MARK: - Tab Bar
    private var tabBar: some View {
        HStack(spacing: 0) {
            ForEach(Tab.allCases, id: \.self) { tab in
                tabButton(tab)
            }
            
            Spacer()
            
            // Add button
            Button {
                if selectedTab == .tags {
                    showAddTag = true
                } else {
                    showAddLabel = true
                }
            } label: {
                Label(selectedTab == .tags ? "New Tag" : "Add Label", systemImage: "plus")
                    .font(HawalaTheme.Typography.body)
            }
            .buttonStyle(.borderedProminent)
            .tint(HawalaTheme.Colors.accent)
        }
        .padding(.horizontal, HawalaTheme.Spacing.xl)
        .padding(.vertical, HawalaTheme.Spacing.md)
        .background(HawalaTheme.Colors.backgroundSecondary)
    }
    
    private func tabButton(_ tab: Tab) -> some View {
        Button {
            withAnimation(.easeInOut(duration: 0.2)) {
                selectedTab = tab
            }
        } label: {
            VStack(spacing: 4) {
                Text(tab.rawValue)
                    .font(HawalaTheme.Typography.body)
                    .foregroundColor(selectedTab == tab ? HawalaTheme.Colors.accent : HawalaTheme.Colors.textSecondary)
                
                Rectangle()
                    .fill(selectedTab == tab ? HawalaTheme.Colors.accent : Color.clear)
                    .frame(height: 2)
            }
            .padding(.horizontal, HawalaTheme.Spacing.lg)
        }
        .buttonStyle(.plain)
    }
    
    // MARK: - Labels List
    private var labelsListView: some View {
        let filteredLabels = searchText.isEmpty ? labelManager.labels : labelManager.search(searchText)
        
        return Group {
            if filteredLabels.isEmpty {
                emptyStateView(
                    icon: "tag.slash",
                    title: "No Address Labels",
                    subtitle: "Add labels to organize your addresses and identify recipients easily."
                )
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(filteredLabels) { label in
                            labelRow(label)
                            Divider()
                                .background(HawalaTheme.Colors.divider)
                        }
                    }
                    .padding(.horizontal, HawalaTheme.Spacing.xl)
                }
            }
        }
    }
    
    private func labelRow(_ label: AddressLabel) -> some View {
        HStack(spacing: HawalaTheme.Spacing.md) {
            // Favorite indicator
            Button {
                labelManager.toggleFavorite(for: label.address)
            } label: {
                Image(systemName: label.isFavorite ? "star.fill" : "star")
                    .foregroundColor(label.isFavorite ? .yellow : HawalaTheme.Colors.textTertiary)
            }
            .buttonStyle(.plain)
            
            // Label info
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: HawalaTheme.Spacing.sm) {
                    Text(label.name)
                        .font(HawalaTheme.Typography.body)
                        .foregroundColor(HawalaTheme.Colors.textPrimary)
                    
                    // Tags
                    ForEach(labelManager.tags(for: label.address)) { tag in
                        tagPill(tag)
                    }
                }
                
                Text(truncateAddress(label.address))
                    .font(HawalaTheme.Typography.monoSmall)
                    .foregroundColor(HawalaTheme.Colors.textSecondary)
                
                if let notes = label.notes, !notes.isEmpty {
                    Text(notes)
                        .font(HawalaTheme.Typography.caption)
                        .foregroundColor(HawalaTheme.Colors.textTertiary)
                        .lineLimit(1)
                }
            }
            
            Spacer()
            
            // Actions
            HStack(spacing: HawalaTheme.Spacing.sm) {
                Button {
                    ClipboardHelper.copySensitive(label.address, timeout: 60)
                    ToastManager.shared.success("Address copied! Auto-clears in 60s.")
                } label: {
                    Image(systemName: "doc.on.doc")
                        .foregroundColor(HawalaTheme.Colors.textSecondary)
                }
                .buttonStyle(.plain)
                
                Button {
                    editingLabel = label
                } label: {
                    Image(systemName: "pencil")
                        .foregroundColor(HawalaTheme.Colors.textSecondary)
                }
                .buttonStyle(.plain)
                
                Button {
                    labelManager.removeLabel(for: label.address)
                } label: {
                    Image(systemName: "trash")
                        .foregroundColor(HawalaTheme.Colors.error)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.vertical, HawalaTheme.Spacing.md)
        .contentShape(Rectangle())
    }
    
    // MARK: - Tags List
    private var tagsListView: some View {
        Group {
            if labelManager.tags.isEmpty {
                emptyStateView(
                    icon: "tag.slash",
                    title: "No Tags",
                    subtitle: "Create tags to categorize your addresses."
                )
            } else {
                ScrollView {
                    LazyVGrid(columns: [
                        GridItem(.flexible()),
                        GridItem(.flexible()),
                        GridItem(.flexible())
                    ], spacing: HawalaTheme.Spacing.md) {
                        ForEach(labelManager.tags) { tag in
                            tagCard(tag)
                        }
                    }
                    .padding(HawalaTheme.Spacing.xl)
                }
            }
        }
    }
    
    private func tagCard(_ tag: AddressTag) -> some View {
        let addressCount = labelManager.addresses(with: tag.id).count
        
        return VStack(alignment: .leading, spacing: HawalaTheme.Spacing.md) {
            HStack {
                Circle()
                    .fill(tag.swiftUIColor)
                    .frame(width: 24, height: 24)
                    .overlay(
                        Group {
                            if let icon = tag.icon {
                                Image(systemName: icon)
                                    .font(.system(size: 12))
                                    .foregroundColor(.white)
                            }
                        }
                    )
                
                Text(tag.name)
                    .font(HawalaTheme.Typography.body)
                    .foregroundColor(HawalaTheme.Colors.textPrimary)
                
                Spacer()
                
                Button {
                    labelManager.deleteTag(tag.id)
                } label: {
                    Image(systemName: "trash")
                        .foregroundColor(HawalaTheme.Colors.error.opacity(0.7))
                }
                .buttonStyle(.plain)
            }
            
            Text("\(addressCount) address\(addressCount == 1 ? "" : "es")")
                .font(HawalaTheme.Typography.caption)
                .foregroundColor(HawalaTheme.Colors.textSecondary)
        }
        .padding(HawalaTheme.Spacing.lg)
        .background(cardBackground)
        .cornerRadius(HawalaTheme.Radius.lg)
    }
    
    // MARK: - Favorites List
    private var favoritesListView: some View {
        Group {
            if labelManager.favorites.isEmpty {
                emptyStateView(
                    icon: "star.slash",
                    title: "No Favorites",
                    subtitle: "Star addresses to add them to your favorites for quick access."
                )
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(labelManager.favorites) { label in
                            labelRow(label)
                            Divider()
                                .background(HawalaTheme.Colors.divider)
                        }
                    }
                    .padding(.horizontal, HawalaTheme.Spacing.xl)
                }
            }
        }
    }
    
    // MARK: - Helpers
    private func tagPill(_ tag: AddressTag) -> some View {
        HStack(spacing: 4) {
            Circle()
                .fill(tag.swiftUIColor)
                .frame(width: 8, height: 8)
            
            Text(tag.name)
                .font(.system(size: 10))
                .foregroundColor(HawalaTheme.Colors.textSecondary)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .background(tag.swiftUIColor.opacity(0.15))
        .cornerRadius(12)
    }
    
    private func emptyStateView(icon: String, title: String, subtitle: String) -> some View {
        VStack(spacing: HawalaTheme.Spacing.lg) {
            Image(systemName: icon)
                .font(.system(size: 48))
                .foregroundColor(HawalaTheme.Colors.textTertiary)
            
            Text(title)
                .font(HawalaTheme.Typography.h3)
                .foregroundColor(HawalaTheme.Colors.textPrimary)
            
            Text(subtitle)
                .font(HawalaTheme.Typography.body)
                .foregroundColor(HawalaTheme.Colors.textSecondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 300)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(HawalaTheme.Spacing.xxl)
    }
    
    private func truncateAddress(_ address: String) -> String {
        guard address.count > 20 else { return address }
        let prefix = String(address.prefix(10))
        let suffix = String(address.suffix(8))
        return "\(prefix)...\(suffix)"
    }
}

// MARK: - Add Label Sheet

struct AddLabelSheet: View {
    var initialAddress: String
    let onSave: () -> Void
    
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @ObservedObject private var labelManager = AddressLabelManager.shared
    
    @State private var address = ""
    @State private var name = ""
    @State private var notes = ""
    @State private var selectedTagIds: Set<UUID> = []
    @State private var isFavorite = false
    
    private var cardBackground: Color {
        colorScheme == .dark ? Color.white.opacity(0.05) : Color.black.opacity(0.03)
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Add Address Label")
                    .font(HawalaTheme.Typography.h2)
                    .foregroundColor(HawalaTheme.Colors.textPrimary)
                
                Spacer()
                
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title2)
                        .foregroundColor(HawalaTheme.Colors.textSecondary)
                }
                .buttonStyle(.plain)
            }
            .padding(HawalaTheme.Spacing.xl)
            
            Divider()
            
            ScrollView {
                VStack(alignment: .leading, spacing: HawalaTheme.Spacing.lg) {
                    // Address field
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Address")
                            .font(HawalaTheme.Typography.caption)
                            .foregroundColor(HawalaTheme.Colors.textSecondary)
                        
                        TextField("0x... or bc1... or any address", text: $address)
                            .textFieldStyle(.plain)
                            .font(HawalaTheme.Typography.mono)
                            .padding(12)
                            .background(cardBackground)
                            .cornerRadius(8)
                    }
                    
                    // Name field
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Label Name")
                            .font(HawalaTheme.Typography.caption)
                            .foregroundColor(HawalaTheme.Colors.textSecondary)
                        
                        TextField("e.g., Coinbase, My Cold Wallet", text: $name)
                            .textFieldStyle(.plain)
                            .padding(12)
                            .background(cardBackground)
                            .cornerRadius(8)
                    }
                    
                    // Notes field
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Notes (optional)")
                            .font(HawalaTheme.Typography.caption)
                            .foregroundColor(HawalaTheme.Colors.textSecondary)
                        
                        TextField("Additional notes about this address", text: $notes)
                            .textFieldStyle(.plain)
                            .padding(12)
                            .background(cardBackground)
                            .cornerRadius(8)
                    }
                    
                    // Tags
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Tags")
                            .font(HawalaTheme.Typography.caption)
                            .foregroundColor(HawalaTheme.Colors.textSecondary)
                        
                        LazyVGrid(columns: [
                            GridItem(.adaptive(minimum: 100))
                        ], spacing: 8) {
                            ForEach(labelManager.tags) { tag in
                                tagSelector(tag)
                            }
                        }
                    }
                    
                    // Favorite toggle
                    Toggle(isOn: $isFavorite) {
                        HStack {
                            Image(systemName: "star.fill")
                                .foregroundColor(.yellow)
                            Text("Add to Favorites")
                                .font(HawalaTheme.Typography.body)
                        }
                    }
                    .toggleStyle(.checkbox)
                }
                .padding(HawalaTheme.Spacing.xl)
            }
            
            Divider()
            
            // Actions
            HStack {
                Spacer()
                
                Button("Cancel") {
                    dismiss()
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                
                Button("Save") {
                    labelManager.setLabel(
                        for: address,
                        name: name,
                        notes: notes.isEmpty ? nil : notes,
                        tagIds: Array(selectedTagIds),
                        isFavorite: isFavorite
                    )
                    onSave()
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .tint(HawalaTheme.Colors.accent)
                .disabled(address.isEmpty || name.isEmpty)
            }
            .padding(HawalaTheme.Spacing.lg)
        }
        .frame(width: 500, height: 550)
        .background(HawalaTheme.Colors.background)
        .onAppear {
            address = initialAddress
        }
    }
    
    private func tagSelector(_ tag: AddressTag) -> some View {
        let isSelected = selectedTagIds.contains(tag.id)
        
        return Button {
            if isSelected {
                selectedTagIds.remove(tag.id)
            } else {
                selectedTagIds.insert(tag.id)
            }
        } label: {
            HStack(spacing: 6) {
                Circle()
                    .fill(tag.swiftUIColor)
                    .frame(width: 12, height: 12)
                
                Text(tag.name)
                    .font(HawalaTheme.Typography.caption)
                    .foregroundColor(HawalaTheme.Colors.textPrimary)
                
                if isSelected {
                    Image(systemName: "checkmark")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(HawalaTheme.Colors.accent)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(isSelected ? tag.swiftUIColor.opacity(0.2) : cardBackground)
            .cornerRadius(16)
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .strokeBorder(isSelected ? tag.swiftUIColor : Color.clear, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }
}

#if DEBUG
struct AddressLabelsView_Previews: PreviewProvider {
    static var previews: some View {
        AddressLabelsView()
            .frame(width: 700, height: 600)
    }
}
#endif
