import SwiftUI

/// Portfolio header showing total balance and quick action buttons
/// Extracted from ContentView to reduce its size (MVVM Refactor)
struct DashboardHeaderView: View {
    let totalBalanceDisplay: String
    let priceStatusLine: String
    let viewportWidth: CGFloat
    let keys: AllKeys?
    let isGenerating: Bool
    let canAccessSensitiveData: Bool
    
    let onRefreshBalances: () -> Void
    let onSend: () -> Void
    let onReceive: () -> Void
    let onViewKeys: () -> Void
    let onExport: () -> Void
    let onSeedPhrase: () -> Void
    let onHistory: () -> Void
    
    var body: some View {
        VStack(spacing: 12) {
            Text("Total Portfolio Value")
                .font(.caption)
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
                .tracking(0.5)
            
            Text(totalBalanceDisplay)
                .font(.system(size: 40, weight: .bold, design: .rounded))
                .foregroundStyle(
                    LinearGradient(
                        colors: [Color.blue, Color.purple],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
            
            Text(priceStatusLine)
                .font(.caption2)
                .foregroundStyle(.secondary)

            Button {
                onRefreshBalances()
            } label: {
                Label("Refresh Balances", systemImage: "arrow.clockwise")
                    .font(.caption)
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .tint(.blue)
        }
        .frame(maxWidth: headerMaxWidth(for: viewportWidth))
        .padding(.vertical, 20)
        .padding(.horizontal, 16)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(cardBackgroundColor)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Color.primary.opacity(0.08), lineWidth: 1)
        )
    }
    
    // MARK: - Action Buttons
    
    @ViewBuilder
    var actionButtonsRow: some View {
        if viewportWidth < 620 {
            VStack(spacing: 10) {
                actionButtonsContent
            }
        } else {
            HStack(spacing: 10) {
                actionButtonsContent
            }
        }
    }

    @ViewBuilder
    private var actionButtonsContent: some View {
        actionButton(title: "Send", systemImage: "paperplane.fill", color: .orange) {
            onSend()
        }
        .disabled(keys == nil && isGenerating)

        actionButton(title: "Receive", systemImage: "arrow.down.left.and.arrow.up.right", color: .green) {
            onReceive()
        }
        .disabled(keys == nil)

        actionButton(title: "View Keys", systemImage: "doc.richtext", color: .blue) {
            onViewKeys()
        }
        .disabled(!canAccessSensitiveData)

        actionButton(title: "Export", systemImage: "tray.and.arrow.up", color: .purple) {
            onExport()
        }
        .disabled(keys == nil)

        actionButton(title: "Seed Phrase", systemImage: "list.number.rtl", color: .purple) {
            onSeedPhrase()
        }
        
        actionButton(title: "History", systemImage: "clock.arrow.circlepath", color: .cyan) {
            onHistory()
        }
    }
    
    // MARK: - Helpers
    
    @ViewBuilder
    private func actionButton(
        title: String,
        systemImage: String,
        color: Color,
        prominent: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            VStack(spacing: 6) {
                Image(systemName: systemImage)
                    .font(.title2)
                Text(title)
                    .font(.caption)
                    .fontWeight(.medium)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
        }
        .buttonStyle(.bordered)
        .tint(prominent ? color : .secondary)
        .controlSize(.large)
    }
    
    private var cardBackgroundColor: Color {
        #if os(macOS)
        Color(nsColor: .controlBackgroundColor).opacity(0.5)
        #else
        Color(.systemBackground).opacity(0.5)
        #endif
    }
    
    private func headerMaxWidth(for width: CGFloat) -> CGFloat? {
        guard width.isFinite else { return nil }
        if width < 560 {
            return width - 16
        }
        return min(width - 120, 780)
    }
}
