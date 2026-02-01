import SwiftUI
import CryptoKit

// MARK: - Hawala Wallet Profile

/// Represents a single wallet in a multi-wallet setup
struct HawalaWalletProfile: Identifiable, Codable, Equatable {
    let id: UUID
    var name: String
    var emoji: String
    var colorHex: String
    let createdAt: Date
    var lastUsedAt: Date
    let importMethod: WalletImportMethodType
    var isHidden: Bool
    var isPinned: Bool
    
    // Derived wallets info
    var enabledChains: [String]
    var totalAddresses: Int
    
    enum WalletImportMethodType: String, Codable {
        case created
        case seedPhrase
        case privateKey
        case hardwareWallet
        case watchOnly
    }
    
    // Default wallet colors
    static let colors: [String] = [
        "#6366F1", // Indigo
        "#8B5CF6", // Violet
        "#EC4899", // Pink
        "#F43F5E", // Rose
        "#F97316", // Orange
        "#EAB308", // Yellow
        "#22C55E", // Green
        "#14B8A6", // Teal
        "#06B6D4", // Cyan
        "#3B82F6"  // Blue
    ]
    
    // Default wallet emojis
    static let emojis: [String] = [
        "💰", "🏦", "💎", "🚀", "🔐",
        "⭐️", "🌙", "🔥", "💫", "🎯",
        "🏆", "💼", "🎨", "🌈", "⚡️"
    ]
    
    init(
        id: UUID = UUID(),
        name: String,
        emoji: String = "💰",
        colorHex: String? = nil,
        importMethod: WalletImportMethodType = .created,
        enabledChains: [String] = ["ethereum", "bitcoin"],
        totalAddresses: Int = 0
    ) {
        self.id = id
        self.name = name
        self.emoji = emoji
        self.colorHex = colorHex ?? Self.colors.randomElement()!
        self.createdAt = Date()
        self.lastUsedAt = Date()
        self.importMethod = importMethod
        self.isHidden = false
        self.isPinned = false
        self.enabledChains = enabledChains
        self.totalAddresses = totalAddresses
    }
    
    var color: Color {
        Color(hex: colorHex)
    }
}

// MARK: - Multi-Wallet Manager

@MainActor
final class MultiWalletManager: ObservableObject {
    
    // MARK: - Published State
    @Published private(set) var wallets: [HawalaWalletProfile] = []
    @Published private(set) var activeWalletId: UUID?
    @Published var isLoading = false
    @Published var error: String?
    
    // MARK: - Storage Keys
    private let walletsKey = "hawala.wallets.profiles"
    private let activeWalletKey = "hawala.wallets.active"
    
    // MARK: - Limits
    static let maxWallets = 10
    static let maxWatchOnly = 20
    
    // MARK: - Singleton
    static let shared = MultiWalletManager()
    
    private init() {
        loadState()
    }
    
    // MARK: - Computed Properties
    
    var activeWallet: HawalaWalletProfile? {
        guard let id = activeWalletId else { return wallets.first }
        return wallets.first { $0.id == id }
    }
    
    var visibleWallets: [HawalaWalletProfile] {
        wallets.filter { !$0.isHidden }
    }
    
    var pinnedWallets: [HawalaWalletProfile] {
        wallets.filter { $0.isPinned && !$0.isHidden }
    }
    
    var regularWallets: [HawalaWalletProfile] {
        wallets.filter { !$0.isPinned && !$0.isHidden }
    }
    
    var sortedWallets: [HawalaWalletProfile] {
        pinnedWallets + regularWallets.sorted { $0.lastUsedAt > $1.lastUsedAt }
    }
    
    var canAddWallet: Bool {
        wallets.filter { $0.importMethod != .watchOnly }.count < Self.maxWallets
    }
    
    var canAddWatchOnly: Bool {
        wallets.filter { $0.importMethod == .watchOnly }.count < Self.maxWatchOnly
    }
    
    // MARK: - Wallet CRUD
    
    func createWallet(name: String, emoji: String = "💰", colorHex: String? = nil, chains: [String] = ["ethereum", "bitcoin"]) -> HawalaWalletProfile {
        let profile = HawalaWalletProfile(
            name: name,
            emoji: emoji,
            colorHex: colorHex,
            importMethod: .created,
            enabledChains: chains
        )
        
        wallets.append(profile)
        
        if activeWalletId == nil {
            activeWalletId = profile.id
        }
        
        saveState()
        
        #if DEBUG
        print("💼 Created wallet: \(profile.name)")
        #endif
        
        return profile
    }
    
    func importWallet(
        name: String,
        method: HawalaWalletProfile.WalletImportMethodType,
        chains: [String] = ["ethereum", "bitcoin"]
    ) -> HawalaWalletProfile {
        let profile = HawalaWalletProfile(
            name: name,
            emoji: "📥",
            importMethod: method,
            enabledChains: chains
        )
        
        wallets.append(profile)
        activeWalletId = profile.id
        saveState()
        
        #if DEBUG
        print("💼 Imported wallet: \(profile.name) via \(method)")
        #endif
        
        return profile
    }
    
    func updateWallet(_ id: UUID, name: String? = nil, emoji: String? = nil, colorHex: String? = nil, chains: [String]? = nil) {
        guard let index = wallets.firstIndex(where: { $0.id == id }) else { return }
        
        if let name = name { wallets[index].name = name }
        if let emoji = emoji { wallets[index].emoji = emoji }
        if let colorHex = colorHex { wallets[index].colorHex = colorHex }
        if let chains = chains { wallets[index].enabledChains = chains }
        
        saveState()
    }
    
    func deleteWallet(_ id: UUID) {
        guard let index = wallets.firstIndex(where: { $0.id == id }) else { return }
        
        let wallet = wallets[index]
        wallets.remove(at: index)
        
        // If we deleted the active wallet, switch to another
        if activeWalletId == id {
            activeWalletId = wallets.first?.id
        }
        
        saveState()
        
        // Also remove keys from secure storage
        // Note: This should be handled carefully in production
        Task {
            await deleteWalletKeys(id)
        }
        
        #if DEBUG
        print("💼 Deleted wallet: \(wallet.name)")
        #endif
    }
    
    private func deleteWalletKeys(_ id: UUID) async {
        // In production, securely delete the associated keys
        // This is a placeholder for the actual implementation
    }
    
    // MARK: - Wallet Selection
    
    func setActiveWallet(_ id: UUID) {
        guard wallets.contains(where: { $0.id == id }) else { return }
        
        activeWalletId = id
        
        // Update last used time
        if let index = wallets.firstIndex(where: { $0.id == id }) {
            wallets[index].lastUsedAt = Date()
        }
        
        saveState()
        
        // Notify observers
        NotificationCenter.default.post(name: .walletChanged, object: id)
        
        #if DEBUG
        print("💼 Active wallet: \(activeWallet?.name ?? "none")")
        #endif
    }
    
    // MARK: - Wallet Organization
    
    func togglePinned(_ id: UUID) {
        guard let index = wallets.firstIndex(where: { $0.id == id }) else { return }
        wallets[index].isPinned.toggle()
        saveState()
    }
    
    func toggleHidden(_ id: UUID) {
        guard let index = wallets.firstIndex(where: { $0.id == id }) else { return }
        wallets[index].isHidden.toggle()
        
        // If hiding the active wallet, switch to another
        if wallets[index].isHidden && activeWalletId == id {
            activeWalletId = visibleWallets.first?.id
        }
        
        saveState()
    }
    
    func reorderWallets(from source: IndexSet, to destination: Int) {
        wallets.move(fromOffsets: source, toOffset: destination)
        saveState()
    }
    
    // MARK: - Wallet Lookup
    
    func wallet(for id: UUID) -> HawalaWalletProfile? {
        wallets.first { $0.id == id }
    }
    
    func wallet(named name: String) -> HawalaWalletProfile? {
        wallets.first { $0.name.lowercased() == name.lowercased() }
    }
    
    // MARK: - Watch-Only Wallets
    
    func addWatchOnlyWallet(address: String, chain: String, name: String? = nil) -> HawalaWalletProfile? {
        guard canAddWatchOnly else { return nil }
        
        let walletName = name ?? "Watch: \(address.prefix(8))..."
        let profile = HawalaWalletProfile(
            name: walletName,
            emoji: "👁️",
            importMethod: .watchOnly,
            enabledChains: [chain],
            totalAddresses: 1
        )
        
        wallets.append(profile)
        saveState()
        
        return profile
    }
    
    // MARK: - Persistence
    
    private func saveState() {
        do {
            let data = try JSONEncoder().encode(wallets)
            UserDefaults.standard.set(data, forKey: walletsKey)
            
            if let activeId = activeWalletId {
                UserDefaults.standard.set(activeId.uuidString, forKey: activeWalletKey)
            }
        } catch {
            #if DEBUG
            print("❌ Failed to save wallet state: \(error)")
            #endif
        }
    }
    
    private func loadState() {
        if let data = UserDefaults.standard.data(forKey: walletsKey) {
            do {
                wallets = try JSONDecoder().decode([HawalaWalletProfile].self, from: data)
            } catch {
                #if DEBUG
                print("❌ Failed to load wallet state: \(error)")
                #endif
            }
        }
        
        if let activeIdString = UserDefaults.standard.string(forKey: activeWalletKey),
           let activeId = UUID(uuidString: activeIdString) {
            activeWalletId = activeId
        } else {
            activeWalletId = wallets.first?.id
        }
    }
    
    // MARK: - Reset
    
    func reset() {
        wallets.removeAll()
        activeWalletId = nil
        UserDefaults.standard.removeObject(forKey: walletsKey)
        UserDefaults.standard.removeObject(forKey: activeWalletKey)
    }
    
    // MARK: - Migration
    
    /// Migrate from single-wallet to multi-wallet if needed
    func migrateFromSingleWallet(name: String = "Main Wallet") {
        guard wallets.isEmpty else { return }
        
        // Check if there's an existing wallet in secure storage
        if SecureSeedStorage.hasSeedPhrase() {
            let profile = HawalaWalletProfile(
                name: name,
                emoji: "💰",
                importMethod: .created,
                enabledChains: PersonaManager.shared.defaultChains
            )
            wallets.append(profile)
            activeWalletId = profile.id
            saveState()
            
            #if DEBUG
            print("💼 Migrated existing wallet to multi-wallet")
            #endif
        }
    }
}

// MARK: - Notifications

extension Notification.Name {
    static let walletChanged = Notification.Name("hawala.wallet.changed")
    static let walletCreated = Notification.Name("hawala.wallet.created")
    static let walletDeleted = Notification.Name("hawala.wallet.deleted")
}

// MARK: - Wallet Picker View

struct WalletPickerSheet: View {
    @ObservedObject var manager = MultiWalletManager.shared
    @Environment(\.dismiss) private var dismiss
    
    let onCreateNew: () -> Void
    let onImport: () -> Void
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Wallets")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(.white)
                
                Spacer()
                
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 22))
                        .foregroundColor(.white.opacity(0.3))
                }
                .buttonStyle(.plain)
            }
            .padding(20)
            
            Divider()
                .background(Color.white.opacity(0.1))
            
            ScrollView {
                VStack(spacing: 8) {
                    // Pinned wallets
                    if !manager.pinnedWallets.isEmpty {
                        Section {
                            ForEach(manager.pinnedWallets) { wallet in
                                WalletRow(wallet: wallet, isActive: wallet.id == manager.activeWalletId) {
                                    manager.setActiveWallet(wallet.id)
                                    dismiss()
                                }
                            }
                        } header: {
                            sectionHeader("Pinned")
                        }
                    }
                    
                    // Regular wallets
                    Section {
                        ForEach(manager.regularWallets) { wallet in
                            WalletRow(wallet: wallet, isActive: wallet.id == manager.activeWalletId) {
                                manager.setActiveWallet(wallet.id)
                                dismiss()
                            }
                        }
                    } header: {
                        sectionHeader("All Wallets")
                    }
                }
                .padding(16)
            }
            
            Divider()
                .background(Color.white.opacity(0.1))
            
            // Actions
            HStack(spacing: 12) {
                Button {
                    onCreateNew()
                    dismiss()
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "plus.circle.fill")
                        Text("Create New")
                    }
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(
                        RoundedRectangle(cornerRadius: 10)
                            .fill(Color.white.opacity(0.1))
                    )
                }
                .buttonStyle(.plain)
                .disabled(!manager.canAddWallet)
                
                Button {
                    onImport()
                    dismiss()
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "square.and.arrow.down")
                        Text("Import")
                    }
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(
                        RoundedRectangle(cornerRadius: 10)
                            .fill(Color.white.opacity(0.1))
                    )
                }
                .buttonStyle(.plain)
            }
            .padding(16)
        }
        .background(Color(hex: "#1C1C1E"))
        .clipShape(RoundedRectangle(cornerRadius: 20))
    }
    
    private func sectionHeader(_ title: String) -> some View {
        HStack {
            Text(title)
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(.white.opacity(0.4))
                .textCase(.uppercase)
            Spacer()
        }
        .padding(.vertical, 8)
    }
}

// MARK: - Wallet Row

private struct WalletRow: View {
    let wallet: HawalaWalletProfile
    let isActive: Bool
    let action: () -> Void
    
    @State private var isHovered = false
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                // Emoji avatar
                ZStack {
                    Circle()
                        .fill(wallet.color.opacity(0.2))
                        .frame(width: 44, height: 44)
                    
                    Text(wallet.emoji)
                        .font(.system(size: 20))
                }
                
                // Info
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(wallet.name)
                            .font(.system(size: 15, weight: .medium))
                            .foregroundColor(.white)
                        
                        if wallet.isPinned {
                            Image(systemName: "pin.fill")
                                .font(.system(size: 10))
                                .foregroundColor(.yellow)
                        }
                        
                        if wallet.importMethod == .watchOnly {
                            Text("Watch")
                                .font(.system(size: 9, weight: .medium))
                                .foregroundColor(.white.opacity(0.5))
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(
                                    Capsule()
                                        .fill(Color.white.opacity(0.1))
                                )
                        }
                    }
                    
                    Text("\(wallet.enabledChains.count) chains")
                        .font(.system(size: 12))
                        .foregroundColor(.white.opacity(0.5))
                }
                
                Spacer()
                
                // Active indicator
                if isActive {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 20))
                        .foregroundColor(.green)
                }
            }
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(isActive ? wallet.color.opacity(0.15) : (isHovered ? Color.white.opacity(0.05) : Color.clear))
            )
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            isHovered = hovering
        }
        .contextMenu {
            Button {
                MultiWalletManager.shared.togglePinned(wallet.id)
            } label: {
                Label(wallet.isPinned ? "Unpin" : "Pin", systemImage: wallet.isPinned ? "pin.slash" : "pin")
            }
            
            Button {
                MultiWalletManager.shared.toggleHidden(wallet.id)
            } label: {
                Label("Hide", systemImage: "eye.slash")
            }
            
            Divider()
            
            Button(role: .destructive) {
                MultiWalletManager.shared.deleteWallet(wallet.id)
            } label: {
                Label("Delete", systemImage: "trash")
            }
        }
    }
}

// MARK: - Wallet Edit Sheet

struct WalletEditSheet: View {
    let walletId: UUID
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var manager = MultiWalletManager.shared
    
    @State private var name: String = ""
    @State private var selectedEmoji: String = "💰"
    @State private var selectedColor: String = "#6366F1"
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Button("Cancel") {
                    dismiss()
                }
                .foregroundColor(.blue)
                
                Spacer()
                
                Text("Edit Wallet")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundColor(.white)
                
                Spacer()
                
                Button("Save") {
                    manager.updateWallet(walletId, name: name, emoji: selectedEmoji, colorHex: selectedColor)
                    dismiss()
                }
                .foregroundColor(.blue)
                .disabled(name.isEmpty)
            }
            .padding(16)
            
            Divider()
                .background(Color.white.opacity(0.1))
            
            ScrollView {
                VStack(spacing: 24) {
                    // Preview
                    ZStack {
                        Circle()
                            .fill(Color(hex: selectedColor).opacity(0.2))
                            .frame(width: 80, height: 80)
                        
                        Text(selectedEmoji)
                            .font(.system(size: 36))
                    }
                    .padding(.top, 24)
                    
                    // Name
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Name")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundColor(.white.opacity(0.6))
                        
                        TextField("Wallet name", text: $name)
                            .textFieldStyle(.plain)
                            .font(.system(size: 16))
                            .padding(12)
                            .background(
                                RoundedRectangle(cornerRadius: 10)
                                    .fill(Color.white.opacity(0.05))
                            )
                    }
                    
                    // Emoji picker
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Emoji")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundColor(.white.opacity(0.6))
                        
                        LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 5), spacing: 8) {
                            ForEach(HawalaWalletProfile.emojis, id: \.self) { emoji in
                                Button {
                                    selectedEmoji = emoji
                                } label: {
                                    Text(emoji)
                                        .font(.system(size: 24))
                                        .frame(width: 44, height: 44)
                                        .background(
                                            Circle()
                                                .fill(selectedEmoji == emoji ? Color.white.opacity(0.2) : Color.clear)
                                        )
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                    
                    // Color picker
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Color")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundColor(.white.opacity(0.6))
                        
                        LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 5), spacing: 8) {
                            ForEach(HawalaWalletProfile.colors, id: \.self) { colorHex in
                                Button {
                                    selectedColor = colorHex
                                } label: {
                                    ZStack {
                                        Circle()
                                            .fill(Color(hex: colorHex))
                                            .frame(width: 44, height: 44)
                                        
                                        if selectedColor == colorHex {
                                            Image(systemName: "checkmark")
                                                .font(.system(size: 16, weight: .bold))
                                                .foregroundColor(.white)
                                        }
                                    }
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }
                .padding(24)
            }
        }
        .background(Color(hex: "#1C1C1E"))
        .onAppear {
            if let wallet = manager.wallet(for: walletId) {
                name = wallet.name
                selectedEmoji = wallet.emoji
                selectedColor = wallet.colorHex
            }
        }
    }
}
