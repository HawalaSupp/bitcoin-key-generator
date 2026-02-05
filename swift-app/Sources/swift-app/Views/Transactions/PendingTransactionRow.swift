import SwiftUI

/// Row view for pending transactions with explorer link and speed-up option
struct PendingTransactionRow: View {
    let transaction: PendingTransactionManager.PendingTransaction
    let onSpeedUp: (() -> Void)?
    let onCancel: (() -> Void)?
    
    init(transaction: PendingTransactionManager.PendingTransaction, onSpeedUp: (() -> Void)? = nil, onCancel: (() -> Void)? = nil) {
        self.transaction = transaction
        self.onSpeedUp = onSpeedUp
        self.onCancel = onCancel
    }
    
    private var timeAgo: String {
        let interval = Date().timeIntervalSince(transaction.timestamp)
        if interval < 60 {
            return "Just now"
        } else if interval < 3600 {
            let mins = Int(interval / 60)
            return "\(mins)m ago"
        } else {
            let hours = Int(interval / 3600)
            return "\(hours)h ago"
        }
    }
    
    var body: some View {
        HStack(spacing: 12) {
            // Animated pending indicator
            ZStack {
                Circle()
                    .stroke(Color.orange.opacity(0.3), lineWidth: 2)
                Circle()
                    .trim(from: 0, to: 0.3)
                    .stroke(Color.orange, style: StrokeStyle(lineWidth: 2, lineCap: .round))
                    .rotationEffect(.degrees(-90))
            }
            .frame(width: 36, height: 36)
            .overlay(
                Image(systemName: "paperplane.fill")
                    .font(.system(size: 14))
                    .foregroundStyle(.orange)
            )
            
            VStack(alignment: .leading, spacing: 3) {
                Text(transaction.chainName)
                    .font(.subheadline)
                    .fontWeight(.semibold)
                Text("To: \(String(transaction.recipient.prefix(8)))...\(String(transaction.recipient.suffix(6)))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            
            Spacer()
            
            VStack(alignment: .trailing, spacing: 3) {
                Text("-\(transaction.amount)")
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .foregroundStyle(.orange)
                
                HStack(spacing: 6) {
                    // Cancel button if available
                    if transaction.canSpeedUp, let cancel = onCancel {
                        Button {
                            cancel()
                        } label: {
                            Label("Cancel", systemImage: "xmark.circle.fill")
                                .font(.caption2)
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.mini)
                        .tint(.red)
                    }
                    
                    // Speed Up button if available
                    if transaction.canSpeedUp, let speedUp = onSpeedUp {
                        Button {
                            speedUp()
                        } label: {
                            Label("Speed Up", systemImage: "bolt.fill")
                                .font(.caption2)
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.mini)
                        .tint(.orange)
                    }
                    
                    Text(transaction.displayStatus)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    
                    if let url = transaction.explorerURL {
                        Link(destination: url) {
                            Image(systemName: "arrow.up.right.square")
                                .font(.caption)
                                .foregroundStyle(.blue)
                        }
                    }
                }
            }
        }
        .padding(.vertical, 10)
    }
}
