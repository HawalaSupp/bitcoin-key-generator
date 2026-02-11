import SwiftUI

// MARK: - ROADMAP-23 E8: Duress Audit Log View

/// Read-only view displaying duress activation history
/// Shows timestamps, device info, and access method for each duress unlock
/// Only accessible when in real (non-duress) mode
struct DuressAuditLogView: View {
    @ObservedObject private var duressManager = DuressWalletManager.shared
    @Environment(\.dismiss) private var dismiss
    
    @State private var logs: [DuressActivationLog] = []
    @State private var showClearConfirmation = false
    
    private var showClearButton: Bool {
        !logs.isEmpty && !duressManager.isInDuressMode
    }
    
    var body: some View {
        NavigationStack {
            mainContent
                .navigationTitle("Security Audit Log")
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Done") { dismiss() }
                    }
                    ToolbarItem(placement: .automatic) {
                        Button("Clear", role: .destructive) {
                            showClearConfirmation = true
                        }
                        .opacity(showClearButton ? 1 : 0)
                        .disabled(!showClearButton)
                    }
                }
                .alert("Clear Audit Log?", isPresented: $showClearConfirmation) {
                Button("Cancel", role: .cancel) { }
                Button("Clear All", role: .destructive) {
                    duressManager.clearDuressLogs()
                    logs = []
                }
            } message: {
                Text("This will permanently delete all duress activation records. This cannot be undone.")
            }
            .onAppear {
                loadLogs()
            }
        }
        .frame(minWidth: 400, minHeight: 350)
    }
    
    // MARK: - Main Content
    
    @ViewBuilder
    private var mainContent: some View {
        if duressManager.isInDuressMode {
            VStack(spacing: 16) {
                Image(systemName: "lock.fill")
                    .font(.system(size: 48))
                    .foregroundColor(.secondary)
                Text("Not Available")
                    .font(.title3)
                    .fontWeight(.semibold)
                Text("This feature is not available in the current mode.")
                    .font(.body)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if logs.isEmpty {
            VStack(spacing: 16) {
                Image(systemName: "clock.badge.checkmark")
                    .font(.system(size: 48))
                    .foregroundColor(.secondary)
                Text("No Activity")
                    .font(.title3)
                    .fontWeight(.semibold)
                Text("No duress activations have been recorded.")
                    .font(.body)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            logList
        }
    }
    
    // MARK: - Log List
    
    private var logList: some View {
        List {
            Section {
                HStack {
                    Image(systemName: "exclamationmark.shield.fill")
                        .foregroundColor(.orange)
                    Text("\(logs.count) duress activation\(logs.count == 1 ? "" : "s") recorded")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
            }
            
            Section("Activation History") {
                ForEach(logs.reversed()) { log in
                    logRow(log)
                }
            }
        }
        .listStyle(.inset)
    }
    
    // MARK: - Log Row
    
    @ViewBuilder
    private func logRow(_ log: DuressActivationLog) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundColor(.red)
                .font(.title3)
            
            VStack(alignment: .leading, spacing: 4) {
                Text("Duress Activation")
                    .font(.subheadline)
                    .fontWeight(.medium)
                
                Text(log.formattedDate)
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                Text("Device: \(log.deviceInfo)")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            Text(relativeTime(from: log.timestamp))
                .font(.caption2)
                .foregroundColor(.secondary)
        }
        .padding(.vertical, 4)
    }
    
    // MARK: - Helpers
    
    private func loadLogs() {
        logs = duressManager.getDuressActivationLogs() ?? []
    }
    
    private func relativeTime(from date: Date) -> String {
        let interval = Date().timeIntervalSince(date)
        if interval < 60 { return "Just now" }
        if interval < 3600 { return "\(Int(interval / 60))m ago" }
        if interval < 86400 { return "\(Int(interval / 3600))h ago" }
        return "\(Int(interval / 86400))d ago"
    }
}
