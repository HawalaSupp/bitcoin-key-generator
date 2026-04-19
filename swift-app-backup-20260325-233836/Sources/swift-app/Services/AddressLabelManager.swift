import Foundation
import SwiftUI

// MARK: - Address Label Manager

/// Manages custom labels and tags for addresses
@MainActor
final class AddressLabelManager: ObservableObject {
    static let shared = AddressLabelManager()
    
    // MARK: - Published Properties
    
    @Published private(set) var labels: [AddressLabel] = []
    @Published private(set) var tags: [AddressTag] = []
    
    // MARK: - Private Properties
    
    private let labelsKey = "hawala_address_labels"
    private let tagsKey = "hawala_address_tags"
    
    // MARK: - Initialization
    
    private init() {
        loadData()
    }
    
    // MARK: - Label Methods
    
    /// Get label for an address
    func label(for address: String) -> AddressLabel? {
        labels.first { $0.address.lowercased() == address.lowercased() }
    }
    
    /// Get display name for an address (label name or truncated address)
    func displayName(for address: String) -> String {
        if let label = label(for: address) {
            return label.name
        }
        return truncateAddress(address)
    }
    
    /// Add or update a label
    func setLabel(for address: String, name: String, notes: String? = nil, tagIds: [UUID] = [], isFavorite: Bool = false) {
        if let index = labels.firstIndex(where: { $0.address.lowercased() == address.lowercased() }) {
            labels[index].name = name
            labels[index].notes = notes
            labels[index].tagIds = tagIds
            labels[index].isFavorite = isFavorite
            labels[index].updatedAt = Date()
        } else {
            let label = AddressLabel(
                address: address,
                name: name,
                notes: notes,
                tagIds: tagIds,
                isFavorite: isFavorite
            )
            labels.append(label)
        }
        saveLabels()
    }
    
    /// Remove a label
    func removeLabel(for address: String) {
        labels.removeAll { $0.address.lowercased() == address.lowercased() }
        saveLabels()
    }
    
    /// Toggle favorite status
    func toggleFavorite(for address: String) {
        if let index = labels.firstIndex(where: { $0.address.lowercased() == address.lowercased() }) {
            labels[index].isFavorite.toggle()
            saveLabels()
        }
    }
    
    /// Get all favorite addresses
    var favorites: [AddressLabel] {
        labels.filter { $0.isFavorite }
    }
    
    /// Search labels
    func search(_ query: String) -> [AddressLabel] {
        guard !query.isEmpty else { return labels }
        let lowercased = query.lowercased()
        return labels.filter {
            $0.name.lowercased().contains(lowercased) ||
            $0.address.lowercased().contains(lowercased) ||
            ($0.notes?.lowercased().contains(lowercased) ?? false)
        }
    }
    
    // MARK: - Tag Methods
    
    /// Get all tags for an address
    func tags(for address: String) -> [AddressTag] {
        guard let label = label(for: address) else { return [] }
        return tags.filter { label.tagIds.contains($0.id) }
    }
    
    /// Create a new tag
    func createTag(name: String, color: String, icon: String? = nil) -> AddressTag {
        let tag = AddressTag(name: name, color: color, icon: icon)
        tags.append(tag)
        saveTags()
        return tag
    }
    
    /// Update a tag
    func updateTag(_ id: UUID, name: String? = nil, color: String? = nil, icon: String? = nil) {
        guard let index = tags.firstIndex(where: { $0.id == id }) else { return }
        if let name = name { tags[index].name = name }
        if let color = color { tags[index].color = color }
        if let icon = icon { tags[index].icon = icon }
        saveTags()
    }
    
    /// Delete a tag
    func deleteTag(_ id: UUID) {
        tags.removeAll { $0.id == id }
        // Remove tag from all labels
        for i in labels.indices {
            labels[i].tagIds.removeAll { $0 == id }
        }
        saveTags()
        saveLabels()
    }
    
    /// Add tag to address
    func addTag(_ tagId: UUID, to address: String) {
        guard let index = labels.firstIndex(where: { $0.address.lowercased() == address.lowercased() }) else { return }
        if !labels[index].tagIds.contains(tagId) {
            labels[index].tagIds.append(tagId)
            saveLabels()
        }
    }
    
    /// Remove tag from address
    func removeTag(_ tagId: UUID, from address: String) {
        guard let index = labels.firstIndex(where: { $0.address.lowercased() == address.lowercased() }) else { return }
        labels[index].tagIds.removeAll { $0 == tagId }
        saveLabels()
    }
    
    /// Get addresses with a specific tag
    func addresses(with tagId: UUID) -> [AddressLabel] {
        labels.filter { $0.tagIds.contains(tagId) }
    }
    
    // MARK: - Default Tags
    
    func createDefaultTags() {
        guard tags.isEmpty else { return }
        
        let defaults: [(name: String, color: String, icon: String)] = [
            ("Personal", "blue", "person.fill"),
            ("Exchange", "orange", "building.columns"),
            ("DeFi", "purple", "square.stack.3d.up"),
            ("Contract", "gray", "doc.text"),
            ("Cold Storage", "cyan", "snowflake"),
            ("Hot Wallet", "red", "flame.fill"),
            ("Business", "green", "briefcase.fill")
        ]
        
        for (name, color, icon) in defaults {
            _ = createTag(name: name, color: color, icon: icon)
        }
    }
    
    // MARK: - Persistence
    
    private func loadData() {
        // Load labels
        if let data = UserDefaults.standard.data(forKey: labelsKey),
           let decoded = try? JSONDecoder().decode([AddressLabel].self, from: data) {
            labels = decoded
        }
        
        // Load tags
        if let data = UserDefaults.standard.data(forKey: tagsKey),
           let decoded = try? JSONDecoder().decode([AddressTag].self, from: data) {
            tags = decoded
        }
        
        // Create default tags if none exist
        if tags.isEmpty {
            createDefaultTags()
        }
    }
    
    private func saveLabels() {
        if let encoded = try? JSONEncoder().encode(labels) {
            UserDefaults.standard.set(encoded, forKey: labelsKey)
        }
    }
    
    private func saveTags() {
        if let encoded = try? JSONEncoder().encode(tags) {
            UserDefaults.standard.set(encoded, forKey: tagsKey)
        }
    }
    
    // MARK: - Helpers
    
    private func truncateAddress(_ address: String) -> String {
        guard address.count > 12 else { return address }
        return "\(address.prefix(6))...\(address.suffix(4))"
    }
}

// MARK: - Address Label Model

struct AddressLabel: Identifiable, Codable, Equatable {
    let id: UUID
    let address: String
    var name: String
    var notes: String?
    var tagIds: [UUID]
    var isFavorite: Bool
    let createdAt: Date
    var updatedAt: Date
    
    init(
        id: UUID = UUID(),
        address: String,
        name: String,
        notes: String? = nil,
        tagIds: [UUID] = [],
        isFavorite: Bool = false
    ) {
        self.id = id
        self.address = address
        self.name = name
        self.notes = notes
        self.tagIds = tagIds
        self.isFavorite = isFavorite
        self.createdAt = Date()
        self.updatedAt = Date()
    }
}

// MARK: - Address Tag Model

struct AddressTag: Identifiable, Codable, Equatable {
    let id: UUID
    var name: String
    var color: String
    var icon: String?
    
    init(id: UUID = UUID(), name: String, color: String, icon: String? = nil) {
        self.id = id
        self.name = name
        self.color = color
        self.icon = icon
    }
    
    var swiftUIColor: Color {
        switch color {
        case "blue": return .blue
        case "green": return .green
        case "orange": return .orange
        case "purple": return .purple
        case "pink": return .pink
        case "cyan": return .cyan
        case "yellow": return .yellow
        case "red": return .red
        case "gray": return .gray
        case "indigo": return .indigo
        case "mint": return .mint
        default: return .blue
        }
    }
}

// MARK: - Address Label Editor View

struct AddressLabelEditorView: View {
    let address: String
    let onSave: () -> Void
    
    @ObservedObject private var manager = AddressLabelManager.shared
    @State private var name = ""
    @State private var notes = ""
    @State private var selectedTagIds: Set<UUID> = []
    @State private var isFavorite = false
    @State private var showCreateTag = false
    
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    
    private var existingLabel: AddressLabel? {
        manager.label(for: address)
    }
    
    private var cardBackground: Color {
        colorScheme == .dark ? Color.white.opacity(0.05) : Color.black.opacity(0.03)
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text(existingLabel != nil ? "Edit Label" : "Add Label")
                    .font(.title2.bold())
                
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
            
            Divider()
            
            ScrollView {
                VStack(spacing: 20) {
                    // Address preview
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Address")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        
                        Text(address)
                            .font(.system(size: 12, design: .monospaced))
                            .foregroundColor(.primary)
                            .padding(12)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(cardBackground)
                            .cornerRadius(8)
                    }
                    
                    // Name field
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Label Name")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        
                        TextField("e.g., My Coinbase", text: $name)
                            .textFieldStyle(.plain)
                            .padding(12)
                            .background(cardBackground)
                            .cornerRadius(8)
                    }
                    
                    // Notes field
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Notes (Optional)")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        
                        TextEditor(text: $notes)
                            .font(.body)
                            .scrollContentBackground(.hidden)
                            .padding(8)
                            .frame(height: 80)
                            .background(cardBackground)
                            .cornerRadius(8)
                    }
                    
                    // Favorite toggle
                    Toggle(isOn: $isFavorite) {
                        HStack {
                            Image(systemName: isFavorite ? "star.fill" : "star")
                                .foregroundColor(isFavorite ? .yellow : .secondary)
                            Text("Add to Favorites")
                        }
                    }
                    .toggleStyle(.switch)
                    .padding(12)
                    .background(cardBackground)
                    .cornerRadius(8)
                    
                    // Tags section
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Text("Tags")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            
                            Spacer()
                            
                            Button {
                                showCreateTag = true
                            } label: {
                                HStack(spacing: 4) {
                                    Image(systemName: "plus")
                                    Text("New Tag")
                                }
                                .font(.caption)
                                .foregroundColor(.blue)
                            }
                            .buttonStyle(.plain)
                        }
                        
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 100))], spacing: 8) {
                            ForEach(manager.tags) { tag in
                                tagButton(tag)
                            }
                        }
                    }
                }
                .padding(20)
            }
            
            Divider()
            
            // Action buttons
            HStack(spacing: 16) {
                if existingLabel != nil {
                    Button {
                        manager.removeLabel(for: address)
                        dismiss()
                    } label: {
                        Text("Delete")
                            .foregroundColor(.red)
                    }
                    .buttonStyle(.plain)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(Color.red.opacity(0.1))
                    .cornerRadius(8)
                }
                
                Spacer()
                
                Button("Cancel") {
                    dismiss()
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(Color.gray.opacity(0.2))
                .cornerRadius(8)
                
                Button("Save") {
                    saveLabel()
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 24)
                .padding(.vertical, 10)
                .background(name.isEmpty ? Color.gray : Color.blue)
                .foregroundColor(.white)
                .cornerRadius(8)
                .disabled(name.isEmpty)
            }
            .padding(20)
        }
        .frame(width: 420, height: 520)
        .onAppear {
            if let label = existingLabel {
                name = label.name
                notes = label.notes ?? ""
                selectedTagIds = Set(label.tagIds)
                isFavorite = label.isFavorite
            }
        }
        .sheet(isPresented: $showCreateTag) {
            CreateTagView(manager: manager)
        }
    }
    
    private func tagButton(_ tag: AddressTag) -> some View {
        let isSelected = selectedTagIds.contains(tag.id)
        
        return Button {
            if isSelected {
                selectedTagIds.remove(tag.id)
            } else {
                selectedTagIds.insert(tag.id)
            }
        } label: {
            HStack(spacing: 6) {
                if let icon = tag.icon {
                    Image(systemName: icon)
                        .font(.caption)
                }
                Text(tag.name)
                    .font(.caption)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(isSelected ? tag.swiftUIColor.opacity(0.3) : cardBackground)
            .foregroundColor(isSelected ? tag.swiftUIColor : .secondary)
            .cornerRadius(16)
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .stroke(isSelected ? tag.swiftUIColor : Color.clear, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }
    
    private func saveLabel() {
        manager.setLabel(
            for: address,
            name: name,
            notes: notes.isEmpty ? nil : notes,
            tagIds: Array(selectedTagIds),
            isFavorite: isFavorite
        )
        onSave()
        dismiss()
    }
}

// MARK: - Create Tag View

struct CreateTagView: View {
    @ObservedObject var manager: AddressLabelManager
    @State private var name = ""
    @State private var selectedColor = "blue"
    @State private var selectedIcon = "tag.fill"
    
    @Environment(\.dismiss) private var dismiss
    
    private let colors = ["blue", "green", "orange", "purple", "pink", "cyan", "yellow", "red", "gray", "indigo"]
    private let icons = ["tag.fill", "person.fill", "building.columns", "square.stack.3d.up", "photo.artframe", "doc.text", "snowflake", "flame.fill", "briefcase.fill", "star.fill", "heart.fill", "bolt.fill"]
    
    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Create Tag")
                    .font(.headline)
                Spacer()
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
            }
            .padding(16)
            
            Divider()
            
            VStack(spacing: 16) {
                TextField("Tag Name", text: $name)
                    .textFieldStyle(.plain)
                    .padding(10)
                    .background(Color.white.opacity(0.05))
                    .cornerRadius(8)
                
                // Color picker
                VStack(alignment: .leading, spacing: 8) {
                    Text("Color")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 5), spacing: 8) {
                        ForEach(colors, id: \.self) { color in
                            Circle()
                                .fill(colorFromString(color))
                                .frame(width: 28, height: 28)
                                .overlay(
                                    selectedColor == color ?
                                    Image(systemName: "checkmark")
                                        .font(.caption.bold())
                                        .foregroundColor(.white)
                                    : nil
                                )
                                .onTapGesture {
                                    selectedColor = color
                                }
                        }
                    }
                }
                
                // Icon picker
                VStack(alignment: .leading, spacing: 8) {
                    Text("Icon")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 6), spacing: 8) {
                        ForEach(icons, id: \.self) { icon in
                            Image(systemName: icon)
                                .font(.body)
                                .frame(width: 32, height: 32)
                                .background(selectedIcon == icon ? colorFromString(selectedColor).opacity(0.3) : Color.white.opacity(0.05))
                                .cornerRadius(6)
                                .onTapGesture {
                                    selectedIcon = icon
                                }
                        }
                    }
                }
            }
            .padding(16)
            
            Divider()
            
            HStack {
                Spacer()
                
                Button("Cancel") {
                    dismiss()
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                
                Button("Create") {
                    _ = manager.createTag(name: name, color: selectedColor, icon: selectedIcon)
                    dismiss()
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 20)
                .padding(.vertical, 8)
                .background(name.isEmpty ? Color.gray : Color.blue)
                .foregroundColor(.white)
                .cornerRadius(8)
                .disabled(name.isEmpty)
            }
            .padding(16)
        }
        .frame(width: 320, height: 380)
    }
    
    private func colorFromString(_ name: String) -> Color {
        switch name {
        case "blue": return .blue
        case "green": return .green
        case "orange": return .orange
        case "purple": return .purple
        case "pink": return .pink
        case "cyan": return .cyan
        case "yellow": return .yellow
        case "red": return .red
        case "gray": return .gray
        case "indigo": return .indigo
        default: return .blue
        }
    }
}

// MARK: - Address Label Badge View

struct AddressLabelBadge: View {
    let address: String
    @ObservedObject private var manager = AddressLabelManager.shared
    
    var body: some View {
        if let label = manager.label(for: address) {
            HStack(spacing: 6) {
                if label.isFavorite {
                    Image(systemName: "star.fill")
                        .font(.system(size: 10))
                        .foregroundColor(.yellow)
                }
                
                Text(label.name)
                    .font(.caption)
                    .foregroundColor(.primary)
                
                // Show first tag color
                if let firstTagId = label.tagIds.first,
                   let tag = manager.tags.first(where: { $0.id == firstTagId }) {
                    Circle()
                        .fill(tag.swiftUIColor)
                        .frame(width: 6, height: 6)
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Color.blue.opacity(0.15))
            .cornerRadius(12)
        }
    }
}
