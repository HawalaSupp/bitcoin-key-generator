import SwiftUI

// MARK: - Token Approvals View

struct TokenApprovalsView: View {
    @StateObject private var manager = TokenApprovalManager.shared
    @Environment(\.dismiss) private var dismiss
    
    let walletAddress: String
    let chainId: Int
    var onRevoke: (TokenApproval) -> Void
    
    @State private var selectedApproval: TokenApproval?
    @State private var showingRevokeConfirmation = false
    @State private var filterRiskLevel: ApprovalRiskLevel?
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            header
            
            // Filter Pills
            filterSection
            
            // Content
            if manager.isLoading {
                loadingView
            } else if let error = manager.lastError {
                errorView(error)
            } else if filteredApprovals.isEmpty {
                emptyView
            } else {
                approvalsList
            }
        }
        .background(HawalaTheme.Colors.background)
        .frame(minWidth: 500, minHeight: 600)
        .task {
            await manager.fetchApprovals(address: walletAddress, chainId: chainId)
        }
        .sheet(isPresented: $showingRevokeConfirmation) {
            if let approval = selectedApproval {
                RevokeConfirmationSheet(
                    approval: approval,
                    onConfirm: {
                        onRevoke(approval)
                        showingRevokeConfirmation = false
                    },
                    onCancel: {
                        showingRevokeConfirmation = false
                    }
                )
            }
        }
    }
    
    private var filteredApprovals: [TokenApproval] {
        guard let filter = filterRiskLevel else {
            return manager.approvals
        }
        return manager.approvals.filter { $0.riskLevel == filter }
    }
    
    // MARK: - Header
    
    private var header: some View {
        VStack(spacing: HawalaTheme.Spacing.sm) {
            HStack {
                Button(action: { dismiss() }) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title2)
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                
                Spacer()
                
                Button(action: {
                    Task {
                        await manager.fetchApprovals(address: walletAddress, chainId: chainId)
                    }
                }) {
                    Image(systemName: "arrow.clockwise")
                        .font(.body)
                }
                .buttonStyle(.bordered)
                .disabled(manager.isLoading)
            }
            .padding(.horizontal, HawalaTheme.Spacing.lg)
            .padding(.top, HawalaTheme.Spacing.md)
            
            VStack(spacing: 4) {
                Text("Token Approvals")
                    .font(HawalaTheme.Typography.h2)
                    .foregroundColor(HawalaTheme.Colors.textPrimary)
                
                Text(chainName)
                    .font(HawalaTheme.Typography.caption)
                    .foregroundColor(HawalaTheme.Colors.textSecondary)
            }
            
            // Stats
            if !manager.approvals.isEmpty {
                HStack(spacing: HawalaTheme.Spacing.lg) {
                    StatPill(
                        value: "\(manager.approvals.count)",
                        label: "Total",
                        color: HawalaTheme.Colors.textSecondary
                    )
                    
                    StatPill(
                        value: "\(highRiskCount)",
                        label: "High Risk",
                        color: .red
                    )
                    
                    StatPill(
                        value: "\(unlimitedCount)",
                        label: "Unlimited",
                        color: .orange
                    )
                }
                .padding(.top, HawalaTheme.Spacing.sm)
            }
        }
        .padding(.bottom, HawalaTheme.Spacing.md)
    }
    
    private var chainName: String {
        switch chainId {
        case 1: return "Ethereum Mainnet"
        case 11155111: return "Sepolia Testnet"
        case 56: return "BNB Chain"
        case 137: return "Polygon"
        default: return "Chain \(chainId)"
        }
    }
    
    private var highRiskCount: Int {
        manager.approvals.filter { $0.riskLevel == .high }.count
    }
    
    private var unlimitedCount: Int {
        manager.approvals.filter { $0.isUnlimited }.count
    }
    
    // MARK: - Filter Section
    
    private var filterSection: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: HawalaTheme.Spacing.sm) {
                ApprovalFilterPill(
                    label: "All",
                    isSelected: filterRiskLevel == nil,
                    action: { filterRiskLevel = nil }
                )
                
                ApprovalFilterPill(
                    label: "High Risk",
                    isSelected: filterRiskLevel == .high,
                    color: .red,
                    action: { filterRiskLevel = .high }
                )
                
                ApprovalFilterPill(
                    label: "Medium",
                    isSelected: filterRiskLevel == .medium,
                    color: .yellow,
                    action: { filterRiskLevel = .medium }
                )
                
                ApprovalFilterPill(
                    label: "Low Risk",
                    isSelected: filterRiskLevel == .low,
                    color: .green,
                    action: { filterRiskLevel = .low }
                )
            }
            .padding(.horizontal, HawalaTheme.Spacing.lg)
        }
        .padding(.vertical, HawalaTheme.Spacing.sm)
    }
    
    // MARK: - Content Views
    
    private var loadingView: some View {
        VStack(spacing: HawalaTheme.Spacing.md) {
            ProgressView()
                .scaleEffect(1.2)
            
            Text("Scanning approvals...")
                .font(HawalaTheme.Typography.body)
                .foregroundColor(HawalaTheme.Colors.textSecondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    private func errorView(_ error: String) -> some View {
        VStack(spacing: HawalaTheme.Spacing.md) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 48))
                .foregroundColor(.orange)
            
            Text("Failed to load approvals")
                .font(HawalaTheme.Typography.h3)
                .foregroundColor(HawalaTheme.Colors.textPrimary)
            
            Text(error)
                .font(HawalaTheme.Typography.caption)
                .foregroundColor(HawalaTheme.Colors.textSecondary)
                .multilineTextAlignment(.center)
            
            Button("Retry") {
                Task {
                    await manager.fetchApprovals(address: walletAddress, chainId: chainId)
                }
            }
            .buttonStyle(.bordered)
        }
        .padding(HawalaTheme.Spacing.xl)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    private var emptyView: some View {
        VStack(spacing: HawalaTheme.Spacing.md) {
            Image(systemName: "checkmark.shield.fill")
                .font(.system(size: 48))
                .foregroundColor(HawalaTheme.Colors.success)
            
            Text("No Active Approvals")
                .font(HawalaTheme.Typography.h3)
                .foregroundColor(HawalaTheme.Colors.textPrimary)
            
            Text("You haven't granted any token spending permissions, or they've all been revoked.")
                .font(HawalaTheme.Typography.body)
                .foregroundColor(HawalaTheme.Colors.textSecondary)
                .multilineTextAlignment(.center)
        }
        .padding(HawalaTheme.Spacing.xl)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    private var approvalsList: some View {
        ScrollView {
            LazyVStack(spacing: HawalaTheme.Spacing.sm) {
                ForEach(filteredApprovals) { approval in
                    ApprovalCard(
                        approval: approval,
                        onRevoke: {
                            selectedApproval = approval
                            showingRevokeConfirmation = true
                        }
                    )
                }
            }
            .padding(HawalaTheme.Spacing.lg)
        }
    }
}

// MARK: - Approval Card

private struct ApprovalCard: View {
    let approval: TokenApproval
    let onRevoke: () -> Void
    
    @State private var isHovered = false
    
    private var riskColor: Color {
        switch approval.riskLevel {
        case .low: return .green
        case .medium: return .yellow
        case .high: return .red
        }
    }
    
    var body: some View {
        HStack(spacing: HawalaTheme.Spacing.md) {
            // Token Icon
            ZStack {
                Circle()
                    .fill(HawalaTheme.Colors.accent.opacity(0.2))
                    .frame(width: 44, height: 44)
                
                Text(approval.tokenSymbol.prefix(2).uppercased())
                    .font(HawalaTheme.Typography.label)
                    .foregroundColor(HawalaTheme.Colors.accent)
            }
            
            // Info
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(approval.tokenName)
                        .font(HawalaTheme.Typography.body)
                        .foregroundColor(HawalaTheme.Colors.textPrimary)
                        .lineLimit(1)
                }
                
                HStack(spacing: 4) {
                    Text("Spender:")
                        .foregroundColor(HawalaTheme.Colors.textTertiary)
                    
                    Text(approval.spenderName ?? formatAddress(approval.spenderAddress))
                        .foregroundColor(HawalaTheme.Colors.textSecondary)
                }
                .font(HawalaTheme.Typography.caption)
                
                // Amount
                HStack(spacing: 4) {
                    Text("Amount:")
                        .foregroundColor(HawalaTheme.Colors.textTertiary)
                    
                    Text(approval.displayAmount)
                        .foregroundColor(approval.isUnlimited ? .orange : HawalaTheme.Colors.textPrimary)
                        .fontWeight(approval.isUnlimited ? .medium : .regular)
                }
                .font(HawalaTheme.Typography.caption)
            }
            
            Spacer()
            
            // Risk indicator & Revoke button
            VStack(alignment: .trailing, spacing: 8) {
                HStack(spacing: 4) {
                    Image(systemName: approval.riskLevel.icon)
                        .font(.caption)
                    Text(riskLabel)
                        .font(HawalaTheme.Typography.label)
                }
                .foregroundColor(riskColor)
                
                Button("Revoke") {
                    onRevoke()
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .tint(.red)
            }
        }
        .padding(HawalaTheme.Spacing.md)
        .background(
            RoundedRectangle(cornerRadius: HawalaTheme.Radius.md)
                .fill(HawalaTheme.Colors.backgroundSecondary)
        )
        .overlay(
            RoundedRectangle(cornerRadius: HawalaTheme.Radius.md)
                .stroke(isHovered ? riskColor.opacity(0.5) : Color.clear, lineWidth: 1)
        )
        .onHover { hovering in
            isHovered = hovering
        }
    }
    
    private var riskLabel: String {
        switch approval.riskLevel {
        case .low: return "Low"
        case .medium: return "Medium"
        case .high: return "High"
        }
    }
    
    private func formatAddress(_ address: String) -> String {
        guard address.count > 12 else { return address }
        return "\(address.prefix(6))...\(address.suffix(4))"
    }
}

// MARK: - Revoke Confirmation Sheet

private struct RevokeConfirmationSheet: View {
    let approval: TokenApproval
    let onConfirm: () -> Void
    let onCancel: () -> Void
    
    var body: some View {
        VStack(spacing: HawalaTheme.Spacing.lg) {
            // Warning Icon
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 48))
                .foregroundColor(.orange)
            
            Text("Revoke Approval")
                .font(HawalaTheme.Typography.h2)
                .foregroundColor(HawalaTheme.Colors.textPrimary)
            
            Text("You're about to revoke the spending permission for:")
                .font(HawalaTheme.Typography.body)
                .foregroundColor(HawalaTheme.Colors.textSecondary)
                .multilineTextAlignment(.center)
            
            // Details
            VStack(alignment: .leading, spacing: HawalaTheme.Spacing.sm) {
                ApprovalDetailRow(label: "Token", value: "\(approval.tokenName) (\(approval.tokenSymbol))")
                ApprovalDetailRow(label: "Spender", value: approval.spenderName ?? approval.spenderAddress)
                ApprovalDetailRow(label: "Current Allowance", value: approval.displayAmount)
            }
            .padding(HawalaTheme.Spacing.md)
            .background(HawalaTheme.Colors.backgroundSecondary)
            .clipShape(RoundedRectangle(cornerRadius: HawalaTheme.Radius.md))
            
            // Note
            HStack(spacing: 8) {
                Image(systemName: "info.circle")
                    .font(.caption)
                Text("This will require a transaction and gas fees.")
                    .font(HawalaTheme.Typography.caption)
            }
            .foregroundColor(HawalaTheme.Colors.textTertiary)
            
            // Actions
            HStack(spacing: HawalaTheme.Spacing.md) {
                Button("Cancel") {
                    onCancel()
                }
                .buttonStyle(.bordered)
                .frame(maxWidth: .infinity)
                
                Button("Revoke") {
                    onConfirm()
                }
                .buttonStyle(.borderedProminent)
                .tint(.red)
                .frame(maxWidth: .infinity)
            }
        }
        .padding(HawalaTheme.Spacing.xl)
        .frame(width: 400)
    }
}

private struct ApprovalDetailRow: View {
    let label: String
    let value: String
    
    var body: some View {
        HStack {
            Text(label)
                .font(HawalaTheme.Typography.caption)
                .foregroundColor(HawalaTheme.Colors.textTertiary)
            
            Spacer()
            
            Text(value)
                .font(HawalaTheme.Typography.body)
                .foregroundColor(HawalaTheme.Colors.textPrimary)
                .lineLimit(1)
                .truncationMode(.middle)
        }
    }
}

// MARK: - Supporting Views

private struct StatPill: View {
    let value: String
    let label: String
    let color: Color
    
    var body: some View {
        VStack(spacing: 2) {
            Text(value)
                .font(HawalaTheme.Typography.h4)
                .foregroundColor(color)
            
            Text(label)
                .font(HawalaTheme.Typography.label)
                .foregroundColor(HawalaTheme.Colors.textTertiary)
        }
    }
}

private struct ApprovalFilterPill: View {
    let label: String
    let isSelected: Bool
    var color: Color = HawalaTheme.Colors.accent
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            Text(label)
                .font(HawalaTheme.Typography.caption)
                .foregroundColor(isSelected ? .white : HawalaTheme.Colors.textSecondary)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(
                    Capsule()
                        .fill(isSelected ? color : HawalaTheme.Colors.backgroundSecondary)
                )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Preview

#if false // Disabled #Preview for command-line builds
#if false
#if false
#Preview {
    TokenApprovalsView(
        walletAddress: "0x742d35Cc6634C0532925a3b844Bc9e7595f2b4F6",
        chainId: 1,
        onRevoke: { _ in }
    )
}
#endif
#endif
#endif
