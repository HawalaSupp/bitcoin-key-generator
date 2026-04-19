import SwiftUI

/// ROADMAP-16 E13: Post-send prompt to save a new recipient address as a contact.
/// Presented after a successful transaction to an address not yet in the address book.
struct SaveContactPromptView: View {
    let address: String
    let chainId: String
    let onSave: (_ name: String, _ notes: String?) -> Void
    let onSkip: () -> Void
    
    @State private var contactName = ""
    @State private var contactNotes = ""
    @Environment(\.dismiss) private var dismiss
    
    /// Shortened address for display
    private var shortAddress: String {
        if address.count > 20 {
            return String(address.prefix(10)) + "..." + String(address.suffix(8))
        }
        return address
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Header illustration
            VStack(spacing: 12) {
                ZStack {
                    Circle()
                        .fill(HawalaTheme.Colors.accent.opacity(0.15))
                        .frame(width: 72, height: 72)
                    Image(systemName: "person.crop.circle.badge.plus")
                        .font(.system(size: 36))
                        .foregroundColor(HawalaTheme.Colors.accent)
                }
                
                Text("Save to Contacts?")
                    .font(.system(size: 20, weight: .bold))
                    .foregroundColor(HawalaTheme.Colors.textPrimary)
                
                Text("You just sent to a new address. Save it for quick access next time.")
                    .font(.subheadline)
                    .foregroundColor(HawalaTheme.Colors.textSecondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 16)
            }
            .padding(.top, 24)
            .padding(.bottom, 20)
            
            Divider()
            
            // Address display
            HStack(spacing: 8) {
                Image(systemName: "wallet.pass")
                    .font(.caption)
                    .foregroundColor(HawalaTheme.Colors.textTertiary)
                Text(shortAddress)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundColor(HawalaTheme.Colors.textSecondary)
                    .lineLimit(1)
                Spacer()
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
            .background(HawalaTheme.Colors.backgroundTertiary)
            
            // Form
            VStack(spacing: 16) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Name")
                        .font(.caption)
                        .fontWeight(.medium)
                        .foregroundColor(HawalaTheme.Colors.textSecondary)
                    TextField("e.g. Alice, Exchange Deposit...", text: $contactName)
                        .textFieldStyle(.roundedBorder)
                        .accessibilityIdentifier("save_contact_name_field")
                }
                
                VStack(alignment: .leading, spacing: 6) {
                    Text("Notes (optional)")
                        .font(.caption)
                        .fontWeight(.medium)
                        .foregroundColor(HawalaTheme.Colors.textSecondary)
                    TextField("Optional note...", text: $contactNotes)
                        .textFieldStyle(.roundedBorder)
                        .accessibilityIdentifier("save_contact_notes_field")
                }
            }
            .padding(20)
            
            Divider()
            
            // Actions
            HStack(spacing: 12) {
                Button("Skip") {
                    onSkip()
                }
                .buttonStyle(.bordered)
                .keyboardShortcut(.cancelAction)
                .accessibilityIdentifier("save_contact_skip_button")
                
                Spacer()
                
                Button("Save Contact") {
                    onSave(
                        contactName.trimmingCharacters(in: .whitespaces),
                        contactNotes.isEmpty ? nil : contactNotes.trimmingCharacters(in: .whitespaces)
                    )
                }
                .buttonStyle(.borderedProminent)
                .disabled(contactName.trimmingCharacters(in: .whitespaces).isEmpty)
                .keyboardShortcut(.defaultAction)
                .accessibilityIdentifier("save_contact_save_button")
            }
            .padding(16)
        }
        .frame(width: 380)
        .background(HawalaTheme.Colors.background)
    }
}
