import SwiftUI

/// Sheet that displays all private keys organized by chain — Hawala glass design
struct AllPrivateKeysSheet: View {
    let chains: [ChainInfo]
    let onCopy: (String) -> Void
    @Environment(\.dismiss) private var dismiss

    @State private var copiedKey: String?

    private var sections: [(chain: ChainInfo, items: [KeyDetail])] {
        chains.compactMap { chain in
            let privateItems = chain.details.filter { $0.label.localizedCaseInsensitiveContains("private") }
            guard !privateItems.isEmpty else { return nil }
            return (chain, privateItems)
        }
    }

    var body: some View {
        HawalaSheetShell(title: "All Private Keys", width: 560, height: 650) {
            if sections.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "key.slash")
                        .font(.system(size: 28, weight: .thin))
                        .foregroundColor(.white.opacity(0.2))
                    Text("No private key fields available.")
                        .font(.system(size: 13))
                        .foregroundColor(.white.opacity(0.35))
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 40)
            } else {
                ForEach(sections, id: \.chain.id) { section in
                    VStack(alignment: .leading, spacing: 10) {
                        HawalaOverlaySectionHeader(icon: "link", title: section.chain.title)

                        ForEach(section.items) { item in
                            VStack(alignment: .leading, spacing: 6) {
                                Text(item.label)
                                    .font(.system(size: 11, weight: .medium))
                                    .foregroundColor(.white.opacity(0.35))

                                HStack(alignment: .top, spacing: 8) {
                                    Text(PrivacyManager.shared.redactAddress(item.value))
                                        .font(.system(size: 12, weight: .regular, design: .monospaced))
                                        .foregroundColor(.white.opacity(0.7))
                                        .textSelection(.enabled)
                                        .lineLimit(3)

                                    Spacer(minLength: 0)

                                    Button {
                                        onCopy(item.value)
                                        copiedKey = item.id.uuidString
                                        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                                            if copiedKey == item.id.uuidString { copiedKey = nil }
                                        }
                                    } label: {
                                        Image(systemName: copiedKey == item.id.uuidString ? "checkmark" : "doc.on.doc")
                                            .font(.system(size: 11, weight: .semibold))
                                            .foregroundColor(copiedKey == item.id.uuidString
                                                ? Color(red: 0.20, green: 0.84, blue: 0.29)
                                                : .white.opacity(0.4))
                                            .frame(width: 28, height: 28)
                                            .background(Color.white.opacity(0.06))
                                            .cornerRadius(6)
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                            .padding(12)
                            .background(Color.white.opacity(0.03))
                            .cornerRadius(10)
                            .overlay(
                                RoundedRectangle(cornerRadius: 10)
                                    .strokeBorder(Color.white.opacity(0.05), lineWidth: 1)
                            )
                        }
                    }
                    .hawalaSectionCard()
                }

                // Warning
                HStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.system(size: 11))
                    Text("Never share your private keys. Anyone with access can steal your funds.")
                        .font(.system(size: 11))
                }
                .foregroundColor(Color(red: 1, green: 0.27, blue: 0.23).opacity(0.7))
                .padding(10)
                .frame(maxWidth: .infinity)
                .background(Color.red.opacity(0.06))
                .cornerRadius(8)
            }
        }
    }
}
