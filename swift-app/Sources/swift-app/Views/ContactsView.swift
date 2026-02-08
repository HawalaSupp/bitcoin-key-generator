import SwiftUI

/// View for managing saved contacts/addresses
struct ContactsView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var contactsManager = ContactsManager.shared
    @State private var searchText = ""
    @State private var showAddContact = false
    @State private var editingContact: Contact?
    @State private var contactToDelete: Contact?
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Button("Done") {
                    dismiss()
                }
                .buttonStyle(.plain)
                .foregroundStyle(.blue)
                
                Spacer()
                
                Text("Address Book")
                    .font(.headline)
                
                Spacer()
                
                Button {
                    showAddContact = true
                } label: {
                    Label("Add Contact", systemImage: "plus")
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
            }
            .padding()
            
            Divider()
            
            // Search
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField("Search contacts...", text: $searchText)
                    .textFieldStyle(.plain)
                if !searchText.isEmpty {
                    Button {
                        searchText = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(8)
            .background(Color.primary.opacity(0.05))
            .cornerRadius(8)
            .padding(.horizontal)
            .padding(.vertical, 8)
            
            // Contacts list
            if filteredContacts.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "person.crop.circle.badge.questionmark")
                        .font(.system(size: 48))
                        .foregroundStyle(.secondary.opacity(0.5))
                    if searchText.isEmpty {
                        Text("No contacts yet")
                            .font(.subheadline)
                            .fontWeight(.medium)
                        Text("Add addresses you send to frequently")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        Text("No matching contacts")
                            .font(.subheadline)
                            .fontWeight(.medium)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding()
            } else {
                List {
                    ForEach(groupedContacts.keys.sorted(), id: \.self) { chainId in
                        Section(header: Text(chainDisplayName(chainId))) {
                            ForEach(groupedContacts[chainId] ?? []) { contact in
                                ContactRow(contact: contact) {
                                    editingContact = contact
                                } onDelete: {
                                    contactToDelete = contact
                                }
                            }
                        }
                    }
                }
                .listStyle(.inset)
            }
        }
        .frame(minWidth: 400, minHeight: 500)
        .sheet(isPresented: $showAddContact) {
            AddEditContactView(contact: nil) { newContact in
                contactsManager.addContact(newContact)
            }
        }
        .sheet(item: $editingContact) { contact in
            AddEditContactView(contact: contact) { updated in
                contactsManager.updateContact(updated)
            }
        }
        .alert("Delete Contact", isPresented: .constant(contactToDelete != nil)) {
            Button("Cancel", role: .cancel) {
                contactToDelete = nil
            }
            Button("Delete", role: .destructive) {
                if let contact = contactToDelete {
                    contactsManager.deleteContact(contact)
                }
                contactToDelete = nil
            }
        } message: {
            if let contact = contactToDelete {
                Text("Are you sure you want to delete \"\(contact.name)\"?")
            }
        }
    }
    
    private var filteredContacts: [Contact] {
        if searchText.isEmpty {
            return contactsManager.contacts
        }
        return contactsManager.search(searchText)
    }
    
    private var groupedContacts: [String: [Contact]] {
        Dictionary(grouping: filteredContacts, by: { $0.chainId })
    }
    
    private func chainDisplayName(_ chainId: String) -> String {
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
}

// MARK: - Contact Row

struct ContactRow: View {
    let contact: Contact
    let onEdit: () -> Void
    let onDelete: () -> Void
    
    @State private var isHovered = false
    @State private var copied = false
    
    var body: some View {
        HStack(spacing: 12) {
            // Avatar
            ZStack {
                Circle()
                    .fill(Color.accentColor.opacity(0.15))
                Text(contact.name.prefix(1).uppercased())
                    .font(.headline)
                    .foregroundStyle(Color.accentColor)
            }
            .frame(width: 40, height: 40)
            
            // Info
            VStack(alignment: .leading, spacing: 2) {
                Text(contact.name)
                    .font(.subheadline)
                    .fontWeight(.semibold)
                Text(contact.shortAddress)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fontDesign(.monospaced)
            }
            
            Spacer()
            
            // Actions (visible on hover)
            if isHovered {
                HStack(spacing: 8) {
                    Button {
                        ClipboardHelper.copySensitive(contact.address, timeout: 60)
                        copied = true
                        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                            copied = false
                        }
                    } label: {
                        Image(systemName: copied ? "checkmark" : "doc.on.doc")
                            .font(.caption)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(copied ? .green : .secondary)
                    
                    Button(action: onEdit) {
                        Image(systemName: "pencil")
                            .font(.caption)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                    
                    Button(action: onDelete) {
                        Image(systemName: "trash")
                            .font(.caption)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.red)
                }
            }
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
        .onHover { hovering in
            isHovered = hovering
        }
    }
}

// MARK: - Add/Edit Contact View

struct AddEditContactView: View {
    let contact: Contact?
    let onSave: (Contact) -> Void
    
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var address = ""
    @State private var selectedChain = "bitcoin"
    @State private var notes = ""
    @State private var addressError: String?
    
    private let chains = [
        ("bitcoin", "Bitcoin"),
        ("bitcoin-testnet", "Bitcoin Testnet"),
        ("litecoin", "Litecoin"),
        ("ethereum", "Ethereum"),
        ("ethereum-sepolia", "Ethereum Testnet"),
        ("bnb", "BNB Chain"),
        ("solana", "Solana"),
        ("xrp", "XRP")
    ]
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text(contact == nil ? "Add Contact" : "Edit Contact")
                    .font(.headline)
                Spacer()
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title2)
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
            .padding()
            
            Divider()
            
            // Form
            Form {
                Section("Contact Info") {
                    TextField("Name", text: $name)
                        .textFieldStyle(.roundedBorder)
                    
                    Picker("Network", selection: $selectedChain) {
                        ForEach(chains, id: \.0) { chain in
                            Text(chain.1).tag(chain.0)
                        }
                    }
                    .onChange(of: selectedChain) { _ in
                        validateAddress()
                    }
                    
                    TextField("Address", text: $address)
                        .textFieldStyle(.roundedBorder)
                        .fontDesign(.monospaced)
                        .onChange(of: address) { _ in
                            validateAddress()
                        }
                    
                    if let error = addressError {
                        Text(error)
                            .font(.caption)
                            .foregroundStyle(.red)
                    }
                }
                
                Section("Notes (Optional)") {
                    TextEditor(text: $notes)
                        .frame(height: 60)
                        .font(.caption)
                }
            }
            .formStyle(.grouped)
            .padding()
            
            Divider()
            
            // Actions
            HStack {
                Button("Cancel") {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)
                
                Spacer()
                
                Button(contact == nil ? "Add Contact" : "Save Changes") {
                    saveContact()
                }
                .buttonStyle(.borderedProminent)
                .disabled(!isValidForm)
                .keyboardShortcut(.defaultAction)
            }
            .padding()
        }
        .frame(width: 400, height: 400)
        .onAppear {
            if let contact = contact {
                name = contact.name
                address = contact.address
                selectedChain = contact.chainId
                notes = contact.notes ?? ""
            }
        }
    }
    
    private var isValidForm: Bool {
        !name.trimmingCharacters(in: .whitespaces).isEmpty &&
        !address.trimmingCharacters(in: .whitespaces).isEmpty &&
        addressError == nil
    }
    
    private func validateAddress() {
        let trimmed = address.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else {
            addressError = nil
            return
        }
        
        // Basic validation based on chain
        let validation: AddressValidationResult
        switch selectedChain {
        case "bitcoin":
            validation = AddressValidator.validateBitcoinAddress(trimmed, network: .bitcoinMainnet)
        case "bitcoin-testnet":
            validation = AddressValidator.validateBitcoinAddress(trimmed, network: .bitcoinTestnet)
        case "litecoin":
            validation = AddressValidator.validateBitcoinAddress(trimmed, network: .litecoinMainnet)
        case "ethereum", "ethereum-sepolia", "bnb":
            validation = AddressValidator.validateEthereumAddress(trimmed)
        case "solana":
            validation = AddressValidator.validateSolanaAddress(trimmed)
        default:
            validation = .valid // Allow other chains
        }
        
        switch validation {
        case .invalid(let reason):
            addressError = reason
        case .valid, .empty:
            addressError = nil
        }
    }
    
    private func saveContact() {
        var newContact: Contact
        if let existing = contact {
            newContact = existing
            newContact.name = name.trimmingCharacters(in: .whitespaces)
            newContact.address = address.trimmingCharacters(in: .whitespaces)
            newContact.chainId = selectedChain
            newContact.notes = notes.isEmpty ? nil : notes
        } else {
            newContact = Contact(
                name: name.trimmingCharacters(in: .whitespaces),
                address: address.trimmingCharacters(in: .whitespaces),
                chainId: selectedChain,
                notes: notes.isEmpty ? nil : notes
            )
        }
        onSave(newContact)
        dismiss()
    }
}

/// Sheet for picking a contact in send views
struct ContactPickerSheet: View {
    let chain: String
    let contacts: [Contact]
    let onSelect: (Contact) -> Void
    let onCancel: () -> Void
    
    @State private var searchText = ""
    
    private var filteredContacts: [Contact] {
        var result = contacts.filter { contact in
            // Filter by compatible chain
            switch chain {
            case "bitcoin", "bitcoin-testnet", "litecoin":
                return contact.chainId == "bitcoin" || contact.chainId == "bitcoin-testnet" || contact.chainId == "litecoin"
            case "ethereum", "ethereum-sepolia", "bnb":
                return contact.chainId == "ethereum" || contact.chainId == "ethereum-sepolia" || contact.chainId == "bnb"
            case "solana":
                return contact.chainId == "solana"
            case "xrp":
                return contact.chainId == "xrp"
            default:
                return contact.chainId == chain
            }
        }
        
        if !searchText.isEmpty {
            result = result.filter { contact in
                contact.name.localizedCaseInsensitiveContains(searchText) ||
                contact.address.localizedCaseInsensitiveContains(searchText)
            }
        }
        
        return result.sorted { $0.name < $1.name }
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Button("Cancel") { onCancel() }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                
                Spacer()
                
                Text("Select Contact")
                    .font(.headline)
                
                Spacer()
                
                // Placeholder for symmetry
                Text("Cancel").opacity(0)
            }
            .padding()
            
            Divider()
            
            // Search
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField("Search...", text: $searchText)
                    .textFieldStyle(.plain)
                if !searchText.isEmpty {
                    Button {
                        searchText = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(8)
            .background(Color.primary.opacity(0.05))
            .cornerRadius(8)
            .padding(.horizontal)
            .padding(.vertical, 8)
            
            // Contact List
            if filteredContacts.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "person.crop.rectangle.stack")
                        .font(.system(size: 48))
                        .foregroundStyle(.secondary)
                    Text(contacts.isEmpty ? "No saved contacts" : "No matching contacts for this chain")
                        .foregroundStyle(.secondary)
                    Text("Add contacts from the Address Book")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(filteredContacts) { contact in
                    Button {
                        onSelect(contact)
                    } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(contact.name)
                                    .font(.headline)
                                    .foregroundStyle(.primary)
                                Text(contact.address)
                                    .font(.system(.caption, design: .monospaced))
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                                    .truncationMode(.middle)
                            }
                            
                            Spacer()
                            
                            Image(systemName: "chevron.right")
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                        }
                        .padding(.vertical, 4)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .frame(minWidth: 400, idealWidth: 450, minHeight: 350, idealHeight: 400)
    }
}

#if false // Disabled #Preview for command-line builds
#if false
#if false
#Preview {
    ContactsView()
}
#endif
#endif
#endif
