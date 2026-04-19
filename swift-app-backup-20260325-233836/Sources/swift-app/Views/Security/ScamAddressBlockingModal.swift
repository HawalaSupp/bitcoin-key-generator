import SwiftUI

// MARK: - Scam Address Blocking Modal (ROADMAP-08 E2)
// Red blocking modal that requires explicit "I understand the risk" acknowledgment
// before allowing a send to a flagged address.

struct ScamAddressBlockingModal: View {
    let address: String
    let riskLevel: AddressRiskLevel
    let reasons: [String]
    let onProceedAnyway: () -> Void
    let onCancel: () -> Void
    
    @State private var acknowledgedRisk = false
    @State private var typedConfirmation = ""
    
    /// Whether this is a hard block (sanctioned = no override possible)
    var isSanctioned: Bool {
        reasons.contains(where: { $0.lowercased().contains("sanctioned") || $0.lowercased().contains("ofac") })
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Red header
            dangerHeader
            
            ScrollView {
                VStack(spacing: 20) {
                    // Address display
                    addressDisplay
                    
                    // Risk reasons
                    riskReasonsList
                    
                    // Sanctioned = hard block, no proceed option
                    if isSanctioned {
                        sanctionedBlock
                    } else {
                        // Acknowledgment section
                        acknowledgmentSection
                    }
                }
                .padding(24)
            }
            
            // Action buttons
            actionButtons
        }
        .frame(minWidth: 420, minHeight: 500)
        .background(Color(nsColor: .windowBackgroundColor))
    }
    
    // MARK: - Danger Header
    
    private var dangerHeader: some View {
        VStack(spacing: 12) {
            Image(systemName: "xmark.octagon.fill")
                .font(.system(size: 48))
                .foregroundColor(.white)
            
            Text(isSanctioned ? "SANCTIONED ADDRESS" : "KNOWN SCAM ADDRESS")
                .font(.system(size: 20, weight: .black))
                .foregroundColor(.white)
            
            Text(isSanctioned
                 ? "This address is on the OFAC sanctions list. Sending to this address is prohibited."
                 : "This address has been flagged as malicious. Sending funds may result in permanent loss.")
                .font(.subheadline)
                .foregroundColor(.white.opacity(0.9))
                .multilineTextAlignment(.center)
                .padding(.horizontal)
        }
        .padding(.vertical, 24)
        .frame(maxWidth: .infinity)
        .background(
            LinearGradient(
                colors: [Color.red.opacity(0.95), Color.red.opacity(0.8)],
                startPoint: .top,
                endPoint: .bottom
            )
        )
    }
    
    // MARK: - Address Display
    
    private var addressDisplay: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("FLAGGED ADDRESS")
                .font(.caption.weight(.semibold))
                .foregroundColor(.secondary)
            
            Text(address)
                .font(.system(.body, design: .monospaced))
                .foregroundColor(.red)
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.red.opacity(0.08))
                .cornerRadius(8)
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color.red.opacity(0.3), lineWidth: 1)
                )
        }
    }
    
    // MARK: - Risk Reasons
    
    private var riskReasonsList: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("DETECTED RISKS")
                .font(.caption.weight(.semibold))
                .foregroundColor(.secondary)
            
            VStack(alignment: .leading, spacing: 6) {
                ForEach(reasons.isEmpty ? ["Reported as scam address"] : reasons, id: \.self) { reason in
                    HStack(alignment: .top, spacing: 8) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundColor(.red)
                            .font(.caption)
                        Text(reason)
                            .font(.subheadline)
                            .foregroundColor(.primary)
                    }
                }
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.red.opacity(0.05))
            .cornerRadius(8)
        }
    }
    
    // MARK: - Sanctioned Block
    
    private var sanctionedBlock: some View {
        VStack(spacing: 12) {
            Image(systemName: "hand.raised.fill")
                .font(.title)
                .foregroundColor(.red)
            
            Text("Transaction Blocked")
                .font(.headline)
                .foregroundColor(.red)
            
            Text("Transactions to OFAC-sanctioned addresses are prohibited and cannot be overridden. This is a legal compliance requirement.")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding()
        .frame(maxWidth: .infinity)
        .background(Color.red.opacity(0.08))
        .cornerRadius(12)
    }
    
    // MARK: - Acknowledgment Section
    
    private var acknowledgmentSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("PROCEED AT YOUR OWN RISK")
                .font(.caption.weight(.semibold))
                .foregroundColor(.secondary)
            
            Toggle(isOn: $acknowledgedRisk) {
                Text("I understand this address has been flagged as malicious and I accept the risk of permanent fund loss.")
                    .font(.subheadline)
                    .foregroundColor(.primary)
            }
            .toggleStyle(.checkbox)
            
            if acknowledgedRisk {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Type \"I UNDERSTAND\" to confirm:")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    TextField("Type here...", text: $typedConfirmation)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(.body, design: .monospaced))
                }
            }
        }
        .padding()
        .background(Color.orange.opacity(0.08))
        .cornerRadius(12)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.orange.opacity(0.3), lineWidth: 1)
        )
    }
    
    // MARK: - Action Buttons
    
    private var canProceed: Bool {
        !isSanctioned && acknowledgedRisk && typedConfirmation.uppercased() == "I UNDERSTAND"
    }
    
    private var actionButtons: some View {
        HStack(spacing: 12) {
            Button(action: onCancel) {
                Text(isSanctioned ? "Close" : "Cancel Transaction")
                    .font(.headline)
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(Color.blue)
                    .cornerRadius(10)
            }
            .buttonStyle(.plain)
            .keyboardShortcut(.escape)
            
            if !isSanctioned {
                Button(action: onProceedAnyway) {
                    Text("Proceed Anyway")
                        .font(.headline)
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(canProceed ? Color.red : Color.gray)
                        .cornerRadius(10)
                }
                .buttonStyle(.plain)
                .disabled(!canProceed)
            }
        }
        .padding(20)
        .background(Color(nsColor: .windowBackgroundColor).shadow(radius: 4, y: -2))
    }
}

// MARK: - Preview

#if DEBUG
struct ScamAddressBlockingModal_Previews: PreviewProvider {
    static var previews: some View {
        ScamAddressBlockingModal(
            address: "0x722122df12d4e14e13ac3b6895a86e84145b6967",
            riskLevel: .critical,
            reasons: ["OFAC Sanctioned", "Tornado Cash", "Money Laundering"],
            onProceedAnyway: {},
            onCancel: {}
        )
    }
}
#endif
