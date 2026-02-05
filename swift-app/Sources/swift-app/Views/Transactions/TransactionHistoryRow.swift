import SwiftUI

/// Row view for displaying a single transaction in history
struct TransactionHistoryRow: View {
    let entry: HawalaTransactionEntry
    @State private var isHovered = false
    @State private var isExpanded = false
    @State private var noteText: String = ""
    @State private var isEditingNote = false

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Image(systemName: iconForType(entry.type))
                    .font(.title3)
                    .foregroundStyle(colorForType(entry.type))
                    .frame(width: 36, height: 36)
                    .background(colorForType(entry.type).opacity(0.15))
                    .clipShape(Circle())
                
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 4) {
                        Text(entry.asset)
                            .font(.subheadline)
                            .fontWeight(.semibold)
                        if hasNote {
                            Image(systemName: "note.text")
                                .font(.caption2)
                                .foregroundStyle(.orange)
                        }
                    }
                    HStack(spacing: 4) {
                        Text(entry.timestamp)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        if let confs = entry.confirmationsDisplay {
                            Text("•")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Text(confs)
                                .font(.caption)
                                .foregroundStyle(confirmationsColor)
                        }
                    }
                }
                
                Spacer()
                
                VStack(alignment: .trailing, spacing: 3) {
                    Text(entry.amountDisplay)
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .foregroundStyle(amountColor)
                    HStack(spacing: 4) {
                        if let fee = entry.fee {
                            Text("Fee: \(fee)")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                        Text(entry.status)
                            .font(.caption)
                            .foregroundStyle(statusColor)
                        if hasDetails {
                            Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .padding(.vertical, 8)
            .contentShape(Rectangle())
            .onHover { hovering in
                isHovered = hovering
            }
            .background(isHovered ? Color.primary.opacity(0.05) : Color.clear)
            .cornerRadius(6)
            .onTapGesture {
                if hasDetails {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        isExpanded.toggle()
                    }
                }
            }
            
            // Expandable details section
            if isExpanded {
                VStack(alignment: .leading, spacing: 6) {
                    Divider()
                        .padding(.leading, 48)
                    
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            if let hash = entry.txHash {
                                HStack(spacing: 4) {
                                    Text("TX Hash:")
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                    Text(String(hash.prefix(16)) + "..." + String(hash.suffix(8)))
                                        .font(.caption2.monospaced())
                                        .foregroundStyle(.primary)
                                    Button {
                                        #if canImport(AppKit)
                                        NSPasteboard.general.clearContents()
                                        NSPasteboard.general.setString(hash, forType: .string)
                                        #endif
                                    } label: {
                                        Image(systemName: "doc.on.doc")
                                            .font(.caption2)
                                    }
                                    .buttonStyle(.plain)
                                    .foregroundStyle(.secondary)
                                }
                            }
                            
                            if let block = entry.blockNumber {
                                HStack(spacing: 4) {
                                    Text("Block:")
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                    Text("#\(block)")
                                        .font(.caption2.monospaced())
                                        .foregroundStyle(.primary)
                                }
                            }
                            
                            if let fee = entry.fee {
                                HStack(spacing: 4) {
                                    Text("Network Fee:")
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                    Text(fee)
                                        .font(.caption2.monospaced())
                                        .foregroundStyle(.primary)
                                }
                            }
                            
                            // Note/Label section
                            VStack(alignment: .leading, spacing: 4) {
                                HStack(spacing: 4) {
                                    Text("Note:")
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                    if !isEditingNote {
                                        Button {
                                            isEditingNote = true
                                        } label: {
                                            Image(systemName: "pencil")
                                                .font(.caption2)
                                        }
                                        .buttonStyle(.plain)
                                        .foregroundStyle(.secondary)
                                    }
                                }
                                
                                if isEditingNote {
                                    HStack {
                                        TextField("Add a note...", text: $noteText)
                                            .textFieldStyle(.roundedBorder)
                                            .font(.caption)
                                            .frame(maxWidth: 200)
                                        
                                        Button("Save") {
                                            if let hash = entry.txHash {
                                                TransactionNotesManager.shared.setNote(noteText, for: hash)
                                            }
                                            isEditingNote = false
                                        }
                                        .buttonStyle(.borderedProminent)
                                        .controlSize(.small)
                                        
                                        Button("Cancel") {
                                            noteText = entry.txHash.flatMap { TransactionNotesManager.shared.getNote(for: $0) } ?? ""
                                            isEditingNote = false
                                        }
                                        .buttonStyle(.bordered)
                                        .controlSize(.small)
                                    }
                                } else if let hash = entry.txHash, let note = TransactionNotesManager.shared.getNote(for: hash), !note.isEmpty {
                                    Text(note)
                                        .font(.caption)
                                        .foregroundStyle(.orange)
                                        .italic()
                                } else {
                                    Text("No note")
                                        .font(.caption2)
                                        .foregroundStyle(.secondary.opacity(0.5))
                                }
                            }
                            .padding(.top, 4)
                        }
                        
                        Spacer()
                        
                        if let url = entry.explorerURL {
                            Button {
                                #if canImport(AppKit)
                                NSWorkspace.shared.open(url)
                                #elseif canImport(UIKit)
                                UIApplication.shared.open(url)
                                #endif
                            } label: {
                                Label("View in Explorer", systemImage: "arrow.up.right.square")
                                    .font(.caption)
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                        }
                    }
                    .padding(.leading, 48)
                    .padding(.vertical, 8)
                }
            }
        }
        .onAppear {
            if let hash = entry.txHash {
                noteText = TransactionNotesManager.shared.getNote(for: hash) ?? ""
            }
        }
    }
    
    private var hasNote: Bool {
        guard let hash = entry.txHash else { return false }
        return TransactionNotesManager.shared.getNote(for: hash) != nil
    }
    
    private var hasDetails: Bool {
        entry.txHash != nil || entry.fee != nil || entry.blockNumber != nil
    }
    
    private var confirmationsColor: Color {
        guard let confs = entry.confirmations else { return .secondary }
        if confs >= 6 {
            return .green
        } else if confs >= 3 {
            return .orange
        } else {
            return .yellow
        }
    }
    
    private var statusColor: Color {
        switch entry.status.lowercased() {
        case "confirmed", "success": return .green
        case "pending": return .orange
        case "failed": return .red
        default: return .secondary
        }
    }
    
    private func iconForType(_ type: String) -> String {
        switch type {
        case "Receive": return "arrow.down.circle.fill"
        case "Send": return "paperplane.fill"
        case "Swap": return "arrow.left.arrow.right.circle.fill"
        case "Stake": return "chart.bar.fill"
        case "Transaction": return "arrow.left.arrow.right"
        default: return "circle.fill"
        }
    }
    
    private func colorForType(_ type: String) -> Color {
        switch type {
        case "Receive": return .green
        case "Send": return .orange
        case "Swap": return .blue
        case "Stake": return .purple
        case "Transaction": return .gray
        default: return .gray
        }
    }
    
    private var amountColor: Color {
        if entry.amountDisplay.hasPrefix("+") {
            return .green
        } else if entry.amountDisplay.hasPrefix("-") {
            return .red
        }
        return .primary
    }
}
