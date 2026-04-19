import SwiftUI

/// Legacy contacts view — replaced by AddressBookOverlay.
/// Kept as a stub so SheetCoordinator references compile.
struct ContactsView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "person.crop.rectangle.stack")
                .font(.system(size: 24))
                .foregroundColor(.white.opacity(0.2))
            Text("Contacts has moved")
                .font(.headline)
                .foregroundColor(.white.opacity(0.6))
            Text("Open Address Book from Settings.")
                .font(.caption)
                .foregroundColor(.white.opacity(0.3))
            Button("Close") { dismiss() }
                .foregroundColor(.white.opacity(0.5))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(red: 0.10, green: 0.10, blue: 0.12))
    }
}

// MARK: - ContactPickerSheet (preserved — used by SendView)

struct ContactPickerSheet: View {
    let chain: String
    let contacts: [Contact]
    let onSelect: (Contact, ContactAddress) -> Void
    let onCancel: () -> Void

    @State private var searchText = ""

    private struct ContactSelection: Identifiable {
        let contact: Contact
        let address: ContactAddress
        var id: String { "\(contact.id.uuidString)-\(address.id.uuidString)" }
    }

    private var filteredContacts: [ContactSelection] {
        var result = contacts.flatMap { contact in
            contact.addresses
                .filter { ContactsManager.chainIDsMatch($0.chainId, chain) }
                .map { ContactSelection(contact: contact, address: $0) }
        }
        if !searchText.isEmpty {
            result = result.filter { sel in
                sel.contact.name.localizedCaseInsensitiveContains(searchText) ||
                sel.address.address.localizedCaseInsensitiveContains(searchText)
            }
        }
        return result.sorted {
            if $0.contact.name == $1.contact.name {
                return $0.address.address < $1.address.address
            }
            return $0.contact.name < $1.contact.name
        }
    }

    var body: some View {
        HawalaSheetShell(title: "Select Contact", width: 420, height: 400) {
            VStack(spacing: 12) {
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 11))
                        .foregroundColor(.white.opacity(0.3))
                    TextField("Search contacts...", text: $searchText)
                        .textFieldStyle(.plain)
                        .font(.system(size: 11))
                        .foregroundColor(.white.opacity(0.8))
                    if !searchText.isEmpty {
                        Button { searchText = "" } label: {
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(size: 10))
                                .foregroundColor(.white.opacity(0.3))
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(8)
                .background(Color.white.opacity(0.05))
                .cornerRadius(8)

                if filteredContacts.isEmpty {
                    VStack(spacing: 10) {
                        Spacer()
                        Image(systemName: "person.crop.rectangle.stack")
                            .font(.system(size: 32))
                            .foregroundColor(.white.opacity(0.15))
                        Text(contacts.isEmpty ? "No saved contacts" : "No matching contacts for this chain")
                            .font(.system(size: 11))
                            .foregroundColor(.white.opacity(0.3))
                        Text("Add contacts from the Address Book")
                            .font(.system(size: 9))
                            .foregroundColor(.white.opacity(0.15))
                        Spacer()
                    }
                    .frame(maxWidth: .infinity)
                } else {
                    ScrollView(.vertical, showsIndicators: false) {
                        LazyVStack(spacing: 4) {
                            ForEach(filteredContacts) { contact in
                                Button {
                                    onSelect(contact.contact, contact.address)
                                } label: {
                                    HStack {
                                        VStack(alignment: .leading, spacing: 3) {
                                            Text(contact.contact.name)
                                                .font(.system(size: 12, weight: .medium))
                                                .foregroundColor(.white.opacity(0.8))
                                            Text(contact.address.address)
                                                .font(.system(size: 9, design: .monospaced))
                                                .foregroundColor(.white.opacity(0.3))
                                                .lineLimit(1)
                                                .truncationMode(.middle)
                                            Text(contact.address.chainDisplayName)
                                                .font(.system(size: 8))
                                                .foregroundColor(.white.opacity(0.2))
                                        }
                                        Spacer()
                                        Image(systemName: "chevron.right")
                                            .font(.system(size: 9))
                                            .foregroundColor(.white.opacity(0.15))
                                    }
                                    .padding(8)
                                    .background(Color.white.opacity(0.03))
                                    .cornerRadius(8)
                                    .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }
            }
        }
    }
}
