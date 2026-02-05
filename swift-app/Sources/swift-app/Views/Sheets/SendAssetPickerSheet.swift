import SwiftUI

/// Sheet for selecting which chain/asset to send
struct SendAssetPickerSheet: View {
    let chains: [ChainInfo]
    let onSelect: (ChainInfo) -> Void
    let onBatchSend: () -> Void
    let onDismiss: () -> Void
    
    @Environment(\.dismiss) private var dismiss
    @State private var searchText = ""
    
    private var filteredChains: [ChainInfo] {
        if searchText.isEmpty { return chains }
        let lowered = searchText.lowercased()
        return chains.filter { $0.title.lowercased().contains(lowered) || $0.subtitle.lowercased().contains(lowered) }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Search bar
                HStack(spacing: 10) {
                    Image(systemName: "magnifyingglass")
                        .foregroundColor(.secondary)
                    TextField("Search assets...", text: $searchText)
                        .textFieldStyle(.plain)
                    if !searchText.isEmpty {
                        Button {
                            searchText = ""
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundColor(.secondary)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(12)
                .background(Color.gray.opacity(0.1))
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .padding()

                ScrollView {
                    LazyVStack(spacing: 12) {
                        // Batch Send option
                        Button {
                            dismiss()
                            onBatchSend()
                        } label: {
                            HStack(spacing: 16) {
                                Image(systemName: "square.stack.3d.up.fill")
                                    .font(.title2)
                                    .foregroundStyle(HawalaTheme.Colors.accent)
                                    .frame(width: 44, height: 44)
                                    .background(HawalaTheme.Colors.accent.opacity(0.1))
                                    .clipShape(Circle())
                                
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("Batch Send")
                                        .font(.headline)
                                        .foregroundStyle(.primary)
                                    Text("Send to multiple addresses at once")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            .padding(12)
                            .background(LinearGradient(
                                colors: [HawalaTheme.Colors.accent.opacity(0.08), HawalaTheme.Colors.accent.opacity(0.02)],
                                startPoint: .leading,
                                endPoint: .trailing
                            ))
                            .clipShape(RoundedRectangle(cornerRadius: 16))
                            .overlay(
                                RoundedRectangle(cornerRadius: 16)
                                    .strokeBorder(HawalaTheme.Colors.accent.opacity(0.2), lineWidth: 1)
                            )
                        }
                        .buttonStyle(.plain)
                        
                        // Divider
                        HStack {
                            VStack { Divider() }
                            Text("or select an asset")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            VStack { Divider() }
                        }
                        .padding(.vertical, 4)
                        
                        ForEach(filteredChains) { chain in
                            Button {
                                dismiss()
                                onSelect(chain)
                            } label: {
                                HStack(spacing: 16) {
                                    Image(systemName: chain.iconName)
                                        .font(.title2)
                                        .foregroundStyle(chain.accentColor)
                                        .frame(width: 44, height: 44)
                                        .background(chain.accentColor.opacity(0.1))
                                        .clipShape(Circle())
                                    
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(chain.title)
                                            .font(.headline)
                                            .foregroundStyle(.primary)
                                        Text(chain.subtitle)
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                    Image(systemName: "chevron.right")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                .padding(12)
                                .background(Color.gray.opacity(0.05))
                                .clipShape(RoundedRectangle(cornerRadius: 16))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal)
                }
            }
            .navigationTitle("Send Funds")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") {
                        dismiss()
                        onDismiss()
                    }
                }
            }
        }
        .frame(width: 450, height: 550)
    }
}
