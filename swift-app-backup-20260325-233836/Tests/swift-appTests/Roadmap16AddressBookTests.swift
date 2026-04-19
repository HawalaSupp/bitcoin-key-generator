import Testing
import Foundation
@testable import swift_app

// MARK: - ROADMAP-16: Address Book & Contacts Tests

@Suite("ROADMAP-16: Contact Model")
struct ContactModelTests {
    
    @Test("Contact initializer sets all fields correctly")
    func contactInit() {
        let contact = Contact(name: "Alice", address: "bc1qtest", chainId: "bitcoin", notes: "My friend")
        #expect(contact.name == "Alice")
        #expect(contact.address == "bc1qtest")
        #expect(contact.chainId == "bitcoin")
        #expect(contact.notes == "My friend")
        #expect(contact.id != UUID()) // unique
    }
    
    @Test("Contact conforms to Codable round-trip")
    func contactCodable() throws {
        let contact = Contact(name: "Bob", address: "0xABC123", chainId: "ethereum", notes: nil)
        let encoded = try JSONEncoder().encode(contact)
        let decoded = try JSONDecoder().decode(Contact.self, from: encoded)
        #expect(decoded.name == contact.name)
        #expect(decoded.address == contact.address)
        #expect(decoded.chainId == contact.chainId)
        #expect(decoded.notes == nil)
        #expect(decoded.id == contact.id)
    }
    
    @Test("Contact conforms to Identifiable")
    func contactIdentifiable() {
        let contact = Contact(name: "Test", address: "addr", chainId: "bitcoin")
        let id: UUID = contact.id
        #expect(id == contact.id)
    }
    
    @Test("Contact conforms to Equatable")
    func contactEquatable() {
        let a = Contact(name: "A", address: "addr1", chainId: "bitcoin")
        let b = Contact(name: "B", address: "addr2", chainId: "ethereum")
        #expect(a != b)
        #expect(a == a)
    }
    
    @Test("Contact chainDisplayName maps correctly")
    func chainDisplayName() {
        let btc = Contact(name: "T", address: "a", chainId: "bitcoin")
        #expect(btc.chainDisplayName == "Bitcoin")
        
        let eth = Contact(name: "T", address: "a", chainId: "ethereum")
        #expect(eth.chainDisplayName == "Ethereum")
        
        let sol = Contact(name: "T", address: "a", chainId: "solana")
        #expect(sol.chainDisplayName == "Solana")
        
        let unknown = Contact(name: "T", address: "a", chainId: "unknown-chain")
        #expect(unknown.chainDisplayName == "Unknown-Chain")
    }
    
    @Test("Contact shortAddress truncates long addresses")
    func shortAddress() {
        let long = Contact(name: "T", address: "bc1q0123456789abcdef0123456789abcdef", chainId: "bitcoin")
        let short = long.shortAddress
        #expect(short.contains("..."))
        #expect(short.hasPrefix("bc1q0123"))
        
        let tiny = Contact(name: "T", address: "short", chainId: "bitcoin")
        #expect(tiny.shortAddress == "short")
    }
}

@Suite("ROADMAP-16: ContactsManager CRUD")
@MainActor
struct ContactsManagerCRUDTests {
    
    @Test("addContact appends to contacts array")
    func addContact() {
        let mgr = ContactsManager.shared
        let before = mgr.contacts.count
        let contact = Contact(name: "TestAdd_\(UUID().uuidString.prefix(6))", address: "test_addr_\(UUID().uuidString)", chainId: "bitcoin")
        mgr.addContact(contact)
        #expect(mgr.contacts.count == before + 1)
        // Cleanup
        mgr.deleteContact(contact)
    }
    
    @Test("deleteContact removes the contact")
    func deleteContact() {
        let mgr = ContactsManager.shared
        let contact = Contact(name: "ToDelete", address: "del_\(UUID().uuidString)", chainId: "bitcoin")
        mgr.addContact(contact)
        let count = mgr.contacts.count
        mgr.deleteContact(contact)
        #expect(mgr.contacts.count == count - 1)
    }
    
    @Test("deleteContact by ID removes the contact")
    func deleteContactById() {
        let mgr = ContactsManager.shared
        let contact = Contact(name: "ToDeleteByID", address: "delid_\(UUID().uuidString)", chainId: "bitcoin")
        mgr.addContact(contact)
        let count = mgr.contacts.count
        mgr.deleteContact(id: contact.id)
        #expect(mgr.contacts.count == count - 1)
    }
    
    @Test("updateContact modifies existing contact")
    func updateContact() {
        let mgr = ContactsManager.shared
        var contact = Contact(name: "Original", address: "upd_\(UUID().uuidString)", chainId: "bitcoin")
        mgr.addContact(contact)
        contact.name = "Updated"
        mgr.updateContact(contact)
        let found = mgr.contacts.first { $0.id == contact.id }
        #expect(found?.name == "Updated")
        // Cleanup
        mgr.deleteContact(contact)
    }
    
    @Test("contacts(for:) filters by chainId")
    func contactsForChain() {
        let mgr = ContactsManager.shared
        let btc = Contact(name: "BTC", address: "btc_\(UUID().uuidString)", chainId: "bitcoin")
        let eth = Contact(name: "ETH", address: "eth_\(UUID().uuidString)", chainId: "ethereum")
        mgr.addContact(btc)
        mgr.addContact(eth)
        
        let btcContacts = mgr.contacts(for: "bitcoin")
        #expect(btcContacts.contains { $0.id == btc.id })
        #expect(!btcContacts.contains { $0.id == eth.id })
        
        // Cleanup
        mgr.deleteContact(btc)
        mgr.deleteContact(eth)
    }
    
    @Test("search finds contacts by name and address")
    func searchContacts() {
        let mgr = ContactsManager.shared
        let contact = Contact(name: "AliceSearch", address: "search_0xABC123", chainId: "ethereum")
        mgr.addContact(contact)
        
        // Search by name
        let byName = mgr.search("AliceSearch")
        #expect(!byName.isEmpty)
        #expect(byName.first?.name == "AliceSearch")
        
        // Search by address (case-insensitive)
        let byAddr = mgr.search("search_0xabc")
        #expect(!byAddr.isEmpty)
        
        // No match
        let noMatch = mgr.search("ZZZnomatch999")
        #expect(noMatch.isEmpty)
        
        // Cleanup
        mgr.deleteContact(contact)
    }
    
    @Test("contact(forAddress:) finds by address case-insensitively")
    func contactForAddress() {
        let mgr = ContactsManager.shared
        let addr = "findme_\(UUID().uuidString)"
        let contact = Contact(name: "FindMe", address: addr, chainId: "solana")
        mgr.addContact(contact)
        
        let found = mgr.contact(forAddress: addr.uppercased())
        #expect(found != nil)
        #expect(found?.name == "FindMe")
        
        // Cleanup
        mgr.deleteContact(contact)
    }
    
    @Test("hasContact(forAddress:) returns true/false correctly")
    func hasContact() {
        let mgr = ContactsManager.shared
        let addr = "has_\(UUID().uuidString)"
        let contact = Contact(name: "HasTest", address: addr, chainId: "bitcoin")
        
        #expect(!mgr.hasContact(forAddress: addr))
        mgr.addContact(contact)
        #expect(mgr.hasContact(forAddress: addr))
        
        // Cleanup
        mgr.deleteContact(contact)
    }
}

@Suite("ROADMAP-16: Import from History")
@MainActor
struct ImportFromHistoryTests {
    
    @Test("unsavedRecentAddresses returns only addresses not in contacts")
    func unsavedRecent() {
        let mgr = ContactsManager.shared
        // Record a send to a unique address via the singleton
        let addr = "unsaved_\(UUID().uuidString)"
        let addrLower = addr.lowercased()
        AddressIntelligenceManager.shared.recordSend(to: addr)
        
        // The address should be in recent recipients now (lowercased by recordSend)
        let recents = AddressIntelligenceManager.shared.getRecentRecipients(limit: 50)
        let inRecents = recents.contains { $0.address == addrLower }
        #expect(inRecents, "Address should appear in recent recipients after recordSend")
        
        // If it's in recents and not in contacts, unsavedRecentAddresses should include it
        if inRecents {
            let unsaved = mgr.unsavedRecentAddresses()
            let found = unsaved.contains { $0.address == addrLower }
            #expect(found)
            
            // Now add as contact — should no longer appear (hasContact is case-insensitive)
            let contact = Contact(name: "Saved", address: addr, chainId: "bitcoin")
            mgr.addContact(contact)
            let unsaved2 = mgr.unsavedRecentAddresses()
            let found2 = unsaved2.contains { $0.address == addrLower }
            #expect(!found2)
            
            // Cleanup
            mgr.deleteContact(contact)
        }
    }
    
    @Test("importFromHistory creates a contact from an address")
    func importSingle() {
        let mgr = ContactsManager.shared
        let addr = "import_\(UUID().uuidString)"
        
        let contact = mgr.importFromHistory(address: addr, chainId: "ethereum", name: "Imported")
        #expect(contact.name == "Imported")
        #expect(contact.address == addr)
        #expect(contact.chainId == "ethereum")
        #expect(mgr.hasContact(forAddress: addr))
        
        // Cleanup
        mgr.deleteContact(contact)
    }
    
    @Test("importFromHistory uses default name when none provided")
    func importDefaultName() {
        let mgr = ContactsManager.shared
        let addr = "defname_\(UUID().uuidString)"
        
        let contact = mgr.importFromHistory(address: addr, chainId: "bitcoin")
        #expect(contact.name.hasPrefix("Recipient"))
        #expect(contact.name.contains(String(addr.prefix(6))))
        
        // Cleanup
        mgr.deleteContact(contact)
    }
}

@Suite("ROADMAP-16: SaveContactPromptView")
@MainActor
struct SaveContactPromptViewTests {
    
    @Test("SaveContactPromptView initializes without crash")
    func viewInit() {
        let _ = SaveContactPromptView(
            address: "bc1qtest123456789",
            chainId: "bitcoin",
            onSave: { _, _ in },
            onSkip: { }
        )
    }
    
    @Test("SaveContactPromptView short address truncation")
    func shortAddressTruncation() {
        // Long address should be truncated
        let longAddr = "bc1q0123456789abcdef0123456789abcdef0123456789"
        #expect(longAddr.count > 20)
        
        // The view should handle this — we just verify the view creates
        let _ = SaveContactPromptView(
            address: longAddr,
            chainId: "bitcoin",
            onSave: { _, _ in },
            onSkip: { }
        )
    }
}

@Suite("ROADMAP-16: ContactPickerSheet")
@MainActor
struct ContactPickerSheetTests {
    
    @Test("ContactPickerSheet initializes with contacts and chain filter")
    func pickerInit() {
        let contacts = [
            Contact(name: "Alice", address: "bc1qalice", chainId: "bitcoin"),
            Contact(name: "Bob", address: "0xbob", chainId: "ethereum"),
        ]
        
        let _ = ContactPickerSheet(
            chain: "bitcoin",
            contacts: contacts,
            onSelect: { _ in },
            onCancel: { }
        )
    }
}

@Suite("ROADMAP-16: Review Data Contact Integration")
@MainActor
struct ReviewContactIntegrationTests {
    
    @Test("TransactionReviewData stores recipientAddress for contact lookup")
    func reviewDataAddress() {
        let data = TransactionReviewData(
            chainId: "bitcoin",
            chainName: "Bitcoin",
            chainIcon: "bitcoinsign.circle.fill",
            symbol: "BTC",
            amount: 0.001,
            recipientAddress: "bc1qsomeaddr",
            recipientDisplayName: nil,
            feeRate: 5.0,
            feeRateUnit: "sat/vB",
            fee: 0.00001,
            feePriority: .average,
            estimatedTime: "~30 min",
            fiatAmount: nil,
            fiatFee: nil,
            currentBalance: nil
        )
        #expect(data.recipientAddress == "bc1qsomeaddr")
    }
    
    @Test("ContactsManager.contact(forAddress:) integrates with review flow")
    @MainActor
    func contactLookupForReview() {
        let mgr = ContactsManager.shared
        let addr = "review_\(UUID().uuidString)"
        let contact = Contact(name: "ReviewContact", address: addr, chainId: "bitcoin")
        mgr.addContact(contact)
        
        // Simulate what TransactionReviewView does
        let found = ContactsManager.shared.contact(forAddress: addr)
        #expect(found != nil)
        #expect(found?.name == "ReviewContact")
        
        // Cleanup
        mgr.deleteContact(contact)
    }
}
