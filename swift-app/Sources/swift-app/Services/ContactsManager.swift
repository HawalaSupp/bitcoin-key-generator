import Foundation

// MARK: - ROADMAP-16 E7: Multi-address per contact

/// A single blockchain address entry within a contact
struct ContactAddress: Codable, Identifiable, Equatable, Hashable {
    let id: UUID
    var address: String
    var chainId: String
    var label: String?
    
    init(address: String, chainId: String, label: String? = nil) {
        self.id = UUID()
        self.address = address
        self.chainId = chainId
        self.label = label
    }
    
    /// Chain display name
    var chainDisplayName: String {
        switch chainId {
        case "bitcoin": return "Bitcoin"
        case "bitcoin-testnet": return "Bitcoin Testnet"
        case "litecoin": return "Litecoin"
        case "ethereum": return "Ethereum"
        case "ethereum-sepolia": return "Ethereum Testnet"
        case "bnb": return "BNB Chain"
        case "solana": return "Solana"
        case "xrp": return "XRP"
        default: return chainId.capitalized
        }
    }
    
    /// Shortened address for display
    var shortAddress: String {
        if address.count > 16 {
            return String(address.prefix(8)) + "..." + String(address.suffix(6))
        }
        return address
    }
}

/// A saved contact/address in the address book
struct Contact: Codable, Identifiable, Equatable {
    let id: UUID
    var name: String
    /// Primary address (kept for backward compatibility)
    var address: String
    /// Primary chain (kept for backward compatibility)
    var chainId: String
    var notes: String?
    var createdAt: Date
    var updatedAt: Date
    /// ROADMAP-16 E7: Multiple addresses per contact
    var addresses: [ContactAddress]
    
    init(name: String, address: String, chainId: String, notes: String? = nil) {
        self.id = UUID()
        self.name = name
        self.address = address
        self.chainId = chainId
        self.notes = notes
        self.createdAt = Date()
        self.updatedAt = Date()
        // Auto-populate addresses array with the primary address
        self.addresses = [ContactAddress(address: address, chainId: chainId, label: "Primary")]
    }
    
    /// Chain display name (from primary address)
    var chainDisplayName: String {
        switch chainId {
        case "bitcoin": return "Bitcoin"
        case "bitcoin-testnet": return "Bitcoin Testnet"
        case "litecoin": return "Litecoin"
        case "ethereum": return "Ethereum"
        case "ethereum-sepolia": return "Ethereum Testnet"
        case "bnb": return "BNB Chain"
        case "solana": return "Solana"
        case "xrp": return "XRP"
        default: return chainId.capitalized
        }
    }
    
    /// Shortened address for display (primary address)
    var shortAddress: String {
        if address.count > 16 {
            return String(address.prefix(8)) + "..." + String(address.suffix(6))
        }
        return address
    }
    
    /// All unique chains this contact has addresses on
    var chains: [String] {
        Array(Set(addresses.map(\.chainId)))
    }
    
    /// Get all addresses for a specific chain
    func addresses(for chainId: String) -> [ContactAddress] {
        addresses.filter { $0.chainId == chainId }
    }
    
    // Custom Codable to handle migration from old format (no `addresses` field)
    enum CodingKeys: String, CodingKey {
        case id, name, address, chainId, notes, createdAt, updatedAt, addresses
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        address = try container.decode(String.self, forKey: .address)
        chainId = try container.decode(String.self, forKey: .chainId)
        notes = try container.decodeIfPresent(String.self, forKey: .notes)
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        updatedAt = try container.decode(Date.self, forKey: .updatedAt)
        
        // Migration: if addresses array is missing, create one from the primary address
        if let addrs = try? container.decode([ContactAddress].self, forKey: .addresses), !addrs.isEmpty {
            addresses = addrs
        } else {
            addresses = [ContactAddress(address: address, chainId: chainId, label: "Primary")]
        }
    }
}

/// Manages the contact address book stored in UserDefaults
@MainActor
class ContactsManager: ObservableObject {
    static let shared = ContactsManager()
    
    private let contactsKey = "hawala.contacts"
    
    @Published private(set) var contacts: [Contact] = []
    
    private init() {
        loadContacts()
    }
    
    /// Add a new contact
    func addContact(_ contact: Contact) {
        contacts.append(contact)
        saveContacts()
    }
    
    /// Update an existing contact
    func updateContact(_ contact: Contact) {
        if let index = contacts.firstIndex(where: { $0.id == contact.id }) {
            var updated = contact
            updated.updatedAt = Date()
            contacts[index] = updated
            saveContacts()
        }
    }
    
    /// Delete a contact
    func deleteContact(_ contact: Contact) {
        contacts.removeAll { $0.id == contact.id }
        saveContacts()
    }
    
    /// Delete contact by ID
    func deleteContact(id: UUID) {
        contacts.removeAll { $0.id == id }
        saveContacts()
    }
    
    /// Get contacts for a specific chain
    func contacts(for chainId: String) -> [Contact] {
        contacts.filter { $0.chainId == chainId }
    }
    
    /// Search contacts by name or address
    func search(_ query: String) -> [Contact] {
        let lowercased = query.lowercased()
        return contacts.filter {
            $0.name.lowercased().contains(lowercased) ||
            $0.address.lowercased().contains(lowercased)
        }
    }
    
    /// Find contact by address
    func contact(forAddress address: String) -> Contact? {
        contacts.first { $0.address.lowercased() == address.lowercased() }
    }
    
    /// Check if address is already saved
    func hasContact(forAddress address: String) -> Bool {
        contacts.contains {
            $0.address.lowercased() == address.lowercased() ||
            $0.addresses.contains { $0.address.lowercased() == address.lowercased() }
        }
    }
    
    // MARK: - ROADMAP-16 E7: Multi-address per contact
    
    /// Add an additional address to an existing contact
    func addAddress(to contactId: UUID, address: ContactAddress) {
        guard let index = contacts.firstIndex(where: { $0.id == contactId }) else { return }
        // Avoid duplicates
        guard !contacts[index].addresses.contains(where: {
            $0.address.lowercased() == address.address.lowercased() && $0.chainId == address.chainId
        }) else { return }
        contacts[index].addresses.append(address)
        contacts[index].updatedAt = Date()
        saveContacts()
    }
    
    /// Remove an address from a contact (cannot remove if only 1 left)
    func removeAddress(from contactId: UUID, addressId: UUID) {
        guard let index = contacts.firstIndex(where: { $0.id == contactId }) else { return }
        guard contacts[index].addresses.count > 1 else { return }
        contacts[index].addresses.removeAll { $0.id == addressId }
        contacts[index].updatedAt = Date()
        saveContacts()
    }
    
    /// Find contact by any of their addresses
    func contact(forAnyAddress address: String) -> Contact? {
        contacts.first {
            $0.addresses.contains { $0.address.lowercased() == address.lowercased() }
        }
    }
    
    /// Get contacts that have an address on the given chain
    func contacts(withChain chainId: String) -> [Contact] {
        contacts.filter { $0.addresses.contains { $0.chainId == chainId } }
    }
    
    // MARK: - ROADMAP-16 E14: Import from transaction history
    
    /// Returns unique sent-to addresses from history that are NOT yet saved as contacts.
    func unsavedRecentAddresses() -> [(address: String, count: Int)] {
        let recents = AddressIntelligenceManager.shared.getRecentRecipients(limit: 50)
        return recents.filter { !hasContact(forAddress: $0.address) }
            .map { (address: $0.address, count: $0.count) }
    }
    
    /// Import an address from history as a new contact with a default name.
    @discardableResult
    func importFromHistory(address: String, chainId: String, name: String? = nil) -> Contact {
        let contactName = name ?? "Recipient \(String(address.prefix(6)))"
        let contact = Contact(name: contactName, address: address, chainId: chainId)
        addContact(contact)
        return contact
    }
    
    /// Bulk-import all unsaved recent addresses. Returns the count of imported contacts.
    @discardableResult
    func importAllFromHistory(chainId: String = "bitcoin") -> Int {
        let unsaved = unsavedRecentAddresses()
        for entry in unsaved {
            importFromHistory(address: entry.address, chainId: chainId)
        }
        return unsaved.count
    }
    
    private func loadContacts() {
        guard let data = UserDefaults.standard.data(forKey: contactsKey),
              let decoded = try? JSONDecoder().decode([Contact].self, from: data) else {
            contacts = []
            return
        }
        contacts = decoded.sorted { $0.name.lowercased() < $1.name.lowercased() }
    }
    
    private func saveContacts() {
        if let data = try? JSONEncoder().encode(contacts) {
            UserDefaults.standard.set(data, forKey: contactsKey)
        }
    }
}
