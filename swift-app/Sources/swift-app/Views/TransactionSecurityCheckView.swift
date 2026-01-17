import SwiftUI

// MARK: - Transaction Security Check View
/// Shows threat assessment and policy check results before transaction signing

struct TransactionSecurityCheckView: View {
    let walletId: String
    let recipient: String
    let amount: String
    let chain: HawalaChain
    let onApprove: () -> Void
    let onReject: () -> Void
    
    @StateObject private var checker = TransactionSecurityChecker()
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            header
            
            Divider()
            
            // Content
            ScrollView {
                VStack(spacing: 20) {
                    if checker.isLoading {
                        loadingView
                    } else {
                        resultsView
                    }
                }
                .padding()
            }
            
            Divider()
            
            // Actions
            actionButtons
        }
        .frame(width: 500, height: 600)
        .onAppear {
            checker.performChecks(walletId: walletId, recipient: recipient, amount: amount, chain: chain)
        }
    }
    
    private var header: some View {
        HStack(spacing: 12) {
            Image(systemName: checker.overallStatus.icon)
                .font(.largeTitle)
                .foregroundColor(checker.overallStatus.color)
            
            VStack(alignment: .leading, spacing: 4) {
                Text("Security Check")
                    .font(.title2.bold())
                Text(checker.overallStatus.message)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            Button(action: { dismiss() }) {
                Image(systemName: "xmark.circle.fill")
                    .font(.title2)
                    .foregroundColor(.secondary)
            }
            .buttonStyle(.plain)
        }
        .padding()
    }
    
    private var loadingView: some View {
        VStack(spacing: 16) {
            ProgressView()
                .scaleEffect(1.5)
            Text("Running security checks...")
                .font(.headline)
            
            VStack(alignment: .leading, spacing: 8) {
                CheckProgressRow(label: "Threat Assessment", isComplete: checker.threatCheckComplete)
                CheckProgressRow(label: "Policy Verification", isComplete: checker.policyCheckComplete)
                CheckProgressRow(label: "Address Analysis", isComplete: checker.addressCheckComplete)
            }
            .padding()
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
    }
    
    private var resultsView: some View {
        VStack(spacing: 20) {
            // Transaction Summary
            TransactionSummaryCard(
                recipient: recipient,
                amount: amount,
                chain: chain
            )
            
            // Threat Assessment Results
            if let threat = checker.threatAssessment {
                ThreatAssessmentCard(assessment: threat)
            }
            
            // Policy Check Results  
            if let policy = checker.policyResult {
                PolicyCheckCard(result: policy)
            }
            
            // Warnings
            if !checker.allWarnings.isEmpty {
                WarningsCard(warnings: checker.allWarnings)
            }
        }
    }
    
    private var actionButtons: some View {
        HStack(spacing: 16) {
            Button(action: {
                onReject()
                dismiss()
            }) {
                Label("Cancel", systemImage: "xmark")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .keyboardShortcut(.escape)
            
            Button(action: {
                onApprove()
                dismiss()
            }) {
                Label(approveButtonText, systemImage: approveButtonIcon)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(checker.overallStatus == .blocked ? .red : .accentColor)
            .disabled(checker.isLoading || checker.overallStatus == .blocked)
            .keyboardShortcut(.return)
        }
        .padding()
    }
    
    private var approveButtonText: String {
        switch checker.overallStatus {
        case .safe: return "Approve Transaction"
        case .warning: return "Proceed Anyway"
        case .blocked: return "Transaction Blocked"
        case .checking: return "Checking..."
        }
    }
    
    private var approveButtonIcon: String {
        switch checker.overallStatus {
        case .safe: return "checkmark.shield"
        case .warning: return "exclamationmark.triangle"
        case .blocked: return "hand.raised.slash"
        case .checking: return "hourglass"
        }
    }
}

// MARK: - Security Checker

@MainActor
class TransactionSecurityChecker: ObservableObject {
    @Published var isLoading = true
    @Published var threatCheckComplete = false
    @Published var policyCheckComplete = false
    @Published var addressCheckComplete = false
    
    @Published var threatAssessment: HawalaBridge.ThreatAssessment?
    @Published var policyResult: HawalaBridge.PolicyCheckResult?
    @Published var overallStatus: SecurityStatus = .checking
    @Published var allWarnings: [String] = []
    
    enum SecurityStatus {
        case checking
        case safe
        case warning
        case blocked
        
        var icon: String {
            switch self {
            case .checking: return "hourglass"
            case .safe: return "checkmark.shield.fill"
            case .warning: return "exclamationmark.triangle.fill"
            case .blocked: return "xmark.shield.fill"
            }
        }
        
        var color: Color {
            switch self {
            case .checking: return .secondary
            case .safe: return .green
            case .warning: return .orange
            case .blocked: return .red
            }
        }
        
        var message: String {
            switch self {
            case .checking: return "Analyzing transaction..."
            case .safe: return "No security concerns detected"
            case .warning: return "Review warnings before proceeding"
            case .blocked: return "Transaction cannot proceed"
            }
        }
    }
    
    func performChecks(walletId: String, recipient: String, amount: String, chain: HawalaChain) {
        isLoading = true
        overallStatus = .checking
        
        Task {
            // Threat Assessment
            do {
                threatAssessment = try HawalaBridge.shared.assessThreat(
                    walletId: walletId,
                    recipient: recipient,
                    amount: amount,
                    chain: chain
                )
                threatCheckComplete = true
                
                if let assessment = threatAssessment {
                    allWarnings.append(contentsOf: assessment.recommendations)
                }
            } catch {
                print("Threat check failed: \(error)")
                threatCheckComplete = true
            }
            
            // Small delay for visual feedback
            try? await Task.sleep(nanoseconds: 200_000_000)
            
            // Policy Check
            do {
                policyResult = try HawalaBridge.shared.checkPolicy(
                    walletId: walletId,
                    recipient: recipient,
                    amount: amount,
                    chain: chain
                )
                policyCheckComplete = true
                
                if let policy = policyResult {
                    allWarnings.append(contentsOf: policy.warnings)
                }
            } catch {
                print("Policy check failed: \(error)")
                policyCheckComplete = true
            }
            
            try? await Task.sleep(nanoseconds: 200_000_000)
            addressCheckComplete = true
            
            // Determine overall status
            determineOverallStatus()
            isLoading = false
        }
    }
    
    private func determineOverallStatus() {
        // Check if blocked
        if let threat = threatAssessment, !threat.allowTransaction {
            overallStatus = .blocked
            return
        }
        
        if let policy = policyResult, !policy.allowed {
            overallStatus = .blocked
            return
        }
        
        // Check for warnings
        let hasThreats = threatAssessment?.threats.isEmpty == false
        let hasViolations = policyResult?.violations.isEmpty == false
        let hasWarnings = !allWarnings.isEmpty
        
        if hasThreats || hasViolations || hasWarnings {
            overallStatus = .warning
        } else {
            overallStatus = .safe
        }
    }
}

// MARK: - Component Views

struct CheckProgressRow: View {
    let label: String
    let isComplete: Bool
    
    var body: some View {
        HStack {
            if isComplete {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundColor(.green)
            } else {
                ProgressView()
                    .scaleEffect(0.7)
            }
            Text(label)
                .font(.subheadline)
            Spacer()
        }
    }
}

struct TransactionSummaryCard: View {
    let recipient: String
    let amount: String
    let chain: HawalaChain
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Transaction Details")
                .font(.headline)
            
            VStack(spacing: 8) {
                HStack {
                    Text("Network")
                        .foregroundColor(.secondary)
                    Spacer()
                    Text(chain.rawValue.capitalized)
                        .fontWeight(.medium)
                }
                
                HStack {
                    Text("Amount")
                        .foregroundColor(.secondary)
                    Spacer()
                    Text(amount)
                        .fontWeight(.medium)
                }
                
                HStack(alignment: .top) {
                    Text("Recipient")
                        .foregroundColor(.secondary)
                    Spacer()
                    Text(formatAddress(recipient))
                        .fontWeight(.medium)
                        .multilineTextAlignment(.trailing)
                }
            }
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(nsColor: .controlBackgroundColor))
        )
    }
    
    private func formatAddress(_ address: String) -> String {
        if address.count > 20 {
            return String(address.prefix(12)) + "..." + String(address.suffix(8))
        }
        return address
    }
}

struct ThreatAssessmentCard: View {
    let assessment: HawalaBridge.ThreatAssessment
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "shield.checkered")
                    .foregroundColor(riskColor)
                Text("Threat Assessment")
                    .font(.headline)
                Spacer()
                RiskBadge(level: assessment.riskLevel)
            }
            
            if !assessment.threats.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(assessment.threats, id: \.description) { threat in
                        HStack(alignment: .top, spacing: 8) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundColor(severityColor(threat.severity))
                                .font(.caption)
                            
                            VStack(alignment: .leading, spacing: 2) {
                                Text(threat.threatType)
                                    .font(.subheadline.weight(.medium))
                                Text(threat.description)
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                }
                .padding()
                .background(Color.red.opacity(0.1), in: RoundedRectangle(cornerRadius: 8))
            } else {
                HStack {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.green)
                    Text("No threats detected")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
            }
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(nsColor: .controlBackgroundColor))
        )
    }
    
    private var riskColor: Color {
        switch assessment.riskLevel.lowercased() {
        case "critical", "high": return .red
        case "medium": return .orange
        default: return .green
        }
    }
    
    private func severityColor(_ severity: String) -> Color {
        switch severity.lowercased() {
        case "critical", "high": return .red
        case "medium": return .orange
        default: return .yellow
        }
    }
}

struct RiskBadge: View {
    let level: String
    
    var body: some View {
        Text(level.uppercased())
            .font(.caption2.bold())
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(badgeColor.opacity(0.2), in: Capsule())
            .foregroundColor(badgeColor)
    }
    
    private var badgeColor: Color {
        switch level.lowercased() {
        case "critical", "high": return .red
        case "medium": return .orange
        case "low": return .yellow
        default: return .green
        }
    }
}

struct PolicyCheckCard: View {
    let result: HawalaBridge.PolicyCheckResult
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "creditcard.trianglebadge.exclamationmark")
                    .foregroundColor(result.allowed ? .green : .red)
                Text("Policy Check")
                    .font(.headline)
                Spacer()
                if result.allowed {
                    Text("PASSED")
                        .font(.caption2.bold())
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.green.opacity(0.2), in: Capsule())
                        .foregroundColor(.green)
                } else {
                    Text("FAILED")
                        .font(.caption2.bold())
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.red.opacity(0.2), in: Capsule())
                        .foregroundColor(.red)
                }
            }
            
            if !result.violations.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(result.violations, id: \.message) { violation in
                        HStack(alignment: .top, spacing: 8) {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundColor(.red)
                                .font(.caption)
                            
                            VStack(alignment: .leading, spacing: 2) {
                                Text(violation.violationType)
                                    .font(.subheadline.weight(.medium))
                                Text(violation.message)
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                }
                .padding()
                .background(Color.red.opacity(0.1), in: RoundedRectangle(cornerRadius: 8))
            }
            
            // Remaining limits
            if let daily = result.remainingDaily {
                HStack {
                    Text("Daily limit remaining:")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Spacer()
                    Text(daily)
                        .font(.caption.weight(.medium))
                }
            }
            
            if let weekly = result.remainingWeekly {
                HStack {
                    Text("Weekly limit remaining:")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Spacer()
                    Text(weekly)
                        .font(.caption.weight(.medium))
                }
            }
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(nsColor: .controlBackgroundColor))
        )
    }
}

struct WarningsCard: View {
    let warnings: [String]
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundColor(.orange)
                Text("Warnings")
                    .font(.headline)
            }
            
            VStack(alignment: .leading, spacing: 8) {
                ForEach(warnings, id: \.self) { warning in
                    HStack(alignment: .top, spacing: 8) {
                        Text("•")
                            .foregroundColor(.orange)
                        Text(warning)
                            .font(.subheadline)
                    }
                }
            }
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.orange.opacity(0.1))
        )
    }
}

// MARK: - Preview

#Preview {
    TransactionSecurityCheckView(
        walletId: "test-wallet",
        recipient: "0x1234567890abcdef1234567890abcdef12345678",
        amount: "0.5 ETH",
        chain: .ethereum,
        onApprove: { print("Approved") },
        onReject: { print("Rejected") }
    )
}
