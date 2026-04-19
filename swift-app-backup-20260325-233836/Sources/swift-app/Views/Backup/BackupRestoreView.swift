import SwiftUI
import UniformTypeIdentifiers

// MARK: - Backup & Restore View

/// Main view for wallet backup and restore operations
struct BackupRestoreView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var walletManager = WalletManager.shared
    
    @State private var selectedTab = 0
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            header
            
            Divider()
            
            // Tab selector
            Picker("", selection: $selectedTab) {
                Text("Export Backup").tag(0)
                Text("Import Backup").tag(1)
            }
            .pickerStyle(.segmented)
            .padding()
            
            // Content
            if selectedTab == 0 {
                ExportBackupView()
            } else {
                ImportBackupView()
            }
        }
        .frame(minWidth: 500, minHeight: 600)
    }
    
    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text("Backup & Restore")
                    .font(.title2.bold())
                Text("Export or import your wallet backup file")
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
}

// MARK: - Export Backup View

struct ExportBackupView: View {
    @ObservedObject private var walletManager = WalletManager.shared
    @State private var password = ""
    @State private var confirmPassword = ""
    @State private var includeSettings = true
    @State private var isExporting = false
    @State private var exportSuccess = false
    @State private var exportError: String?
    @State private var showingFilePicker = false
    
    private let encoder = HawalaFileEncoder.shared
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                // Warning banner
                warningBanner
                
                // Wallet summary
                walletSummary
                
                Divider()
                
                // Password section
                passwordSection
                
                // Options
                optionsSection
                
                Divider()
                
                // Export button
                exportButton
                
                // Status messages
                statusMessages
            }
            .padding()
        }
    }
    
    private var warningBanner: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.title2)
                .foregroundColor(.orange)
            
            VStack(alignment: .leading, spacing: 4) {
                Text("Important Security Information")
                    .font(.headline)
                
                Text("Your backup file contains your seed phrases and can be used to access all your funds. Store it securely and never share it with anyone.")
                    .font(.callout)
                    .foregroundColor(.secondary)
            }
        }
        .padding()
        .background(Color.orange.opacity(0.1))
        .cornerRadius(12)
    }
    
    private var walletSummary: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Wallets to Export")
                .font(.headline)
            
            if walletManager.hdWallets.isEmpty {
                Text("No wallets to export")
                    .foregroundColor(.secondary)
            } else {
                ForEach(walletManager.hdWallets) { wallet in
                    HStack {
                        Image(systemName: "wallet.pass.fill")
                            .foregroundColor(.blue)
                        
                        VStack(alignment: .leading) {
                            Text(wallet.name)
                                .font(.body)
                            Text("\(wallet.accounts.count) accounts")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        
                        Spacer()
                        
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(.green)
                    }
                    .padding(.vertical, 4)
                }
            }
        }
    }
    
    private var passwordSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Encryption Password")
                .font(.headline)
            
            Text("Choose a strong password to encrypt your backup. You'll need this password to restore from this backup.")
                .font(.callout)
                .foregroundColor(.secondary)
            
            SecureField("Password", text: $password)
                .textFieldStyle(.roundedBorder)
            
            // Password strength indicator
            if !password.isEmpty {
                let strength = encoder.evaluatePasswordStrength(password)
                HStack {
                    Text("Strength:")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    Text(strength.description)
                        .font(.caption.bold())
                        .foregroundColor(strengthColor(strength))
                    
                    Spacer()
                    
                    if strength < encoder.minimumRecommendedStrength {
                        Text("Recommended: Good or stronger")
                            .font(.caption)
                            .foregroundColor(.orange)
                    }
                }
            }
            
            SecureField("Confirm Password", text: $confirmPassword)
                .textFieldStyle(.roundedBorder)
            
            if !confirmPassword.isEmpty && password != confirmPassword {
                Text("Passwords don't match")
                    .font(.caption)
                    .foregroundColor(.red)
            }
        }
    }
    
    private var optionsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Options")
                .font(.headline)
            
            Toggle(isOn: $includeSettings) {
                VStack(alignment: .leading) {
                    Text("Include Settings")
                    Text("Currency, theme, and other preferences")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
        }
    }
    
    private var exportButton: some View {
        Button(action: exportBackup) {
            HStack {
                if isExporting {
                    ProgressView()
                        .scaleEffect(0.8)
                        .padding(.trailing, 4)
                } else {
                    Image(systemName: "arrow.down.doc.fill")
                }
                Text(isExporting ? "Exporting..." : "Export Backup")
            }
            .frame(maxWidth: .infinity)
            .padding()
            .background(canExport ? Color.blue : Color.gray)
            .foregroundColor(.white)
            .cornerRadius(10)
        }
        .buttonStyle(.plain)
        .disabled(!canExport || isExporting)
        .fileExporter(
            isPresented: $showingFilePicker,
            document: HawalaBackupDocument(data: exportedData ?? Data()),
            contentType: .hawalaBackup,
            defaultFilename: encoder.suggestedFilename()
        ) { result in
            handleExportResult(result)
        }
    }
    
    @State private var exportedData: Data?
    
    private var statusMessages: some View {
        Group {
            if exportSuccess {
                HStack {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.green)
                    Text("Backup exported successfully!")
                        .foregroundColor(.green)
                }
            }
            
            if let error = exportError {
                HStack {
                    Image(systemName: "exclamationmark.circle.fill")
                        .foregroundColor(.red)
                    Text(error)
                        .foregroundColor(.red)
                }
            }
        }
    }
    
    private var canExport: Bool {
        !walletManager.hdWallets.isEmpty &&
        !password.isEmpty &&
        password == confirmPassword &&
        encoder.evaluatePasswordStrength(password) >= .fair
    }
    
    private func strengthColor(_ strength: HawalaFileEncoder.PasswordStrength) -> Color {
        switch strength {
        case .weak: return .red
        case .fair: return .orange
        case .good: return .yellow
        case .strong: return .green
        }
    }
    
    private func exportBackup() {
        isExporting = true
        exportError = nil
        exportSuccess = false
        
        Task {
            do {
                let data = try await encoder.createBackup(
                    from: walletManager,
                    password: password,
                    includeSettings: includeSettings
                )
                
                await MainActor.run {
                    exportedData = data
                    showingFilePicker = true
                    isExporting = false
                }
            } catch {
                await MainActor.run {
                    exportError = error.localizedDescription
                    isExporting = false
                }
            }
        }
    }
    
    private func handleExportResult(_ result: Result<URL, Error>) {
        switch result {
        case .success:
            exportSuccess = true
            // Clear sensitive data
            password = ""
            confirmPassword = ""
        case .failure(let error):
            if (error as NSError).code != NSUserCancelledError {
                exportError = error.localizedDescription
            }
        }
    }
}

// MARK: - Import Backup View

struct ImportBackupView: View {
    @ObservedObject private var walletManager = WalletManager.shared
    @State private var selectedFileURL: URL?
    @State private var password = ""
    @State private var showingFilePicker = false
    @State private var isImporting = false
    @State private var preview: BackupPreview?
    @State private var importError: String?
    @State private var restorationSummary: RestorationSummary?
    @State private var overwriteExisting = false
    
    private let decoder = HawalaFileDecoder.shared
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                // File selection
                fileSelectionSection
                
                if selectedFileURL != nil {
                    Divider()
                    
                    // Password entry
                    passwordSection
                    
                    // Preview (if unlocked)
                    if let preview = preview {
                        Divider()
                        previewSection(preview)
                    }
                    
                    // Options
                    if preview != nil {
                        optionsSection
                    }
                    
                    Divider()
                    
                    // Import button
                    importButton
                }
                
                // Status messages
                statusMessages
            }
            .padding()
        }
        .fileImporter(
            isPresented: $showingFilePicker,
            allowedContentTypes: [.hawalaBackup, .data],
            allowsMultipleSelection: false
        ) { result in
            handleFileSelection(result)
        }
    }
    
    private var fileSelectionSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Select Backup File")
                .font(.headline)
            
            if let url = selectedFileURL {
                HStack {
                    Image(systemName: "doc.fill")
                        .foregroundColor(.blue)
                    
                    VStack(alignment: .leading) {
                        Text(url.lastPathComponent)
                            .font(.body)
                        Text(url.deletingLastPathComponent().path)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    
                    Spacer()
                    
                    Button("Change") {
                        showingFilePicker = true
                    }
                }
                .padding()
                .background(Color.secondary.opacity(0.1))
                .cornerRadius(8)
            } else {
                Button(action: { showingFilePicker = true }) {
                    HStack {
                        Image(systemName: "folder.badge.plus")
                        Text("Select .hawala File")
                    }
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.blue.opacity(0.1))
                    .foregroundColor(.blue)
                    .cornerRadius(10)
                }
                .buttonStyle(.plain)
            }
        }
    }
    
    private var passwordSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Enter Backup Password")
                .font(.headline)
            
            Text("Enter the password you used when creating this backup.")
                .font(.callout)
                .foregroundColor(.secondary)
            
            HStack {
                SecureField("Password", text: $password)
                    .textFieldStyle(.roundedBorder)
                
                Button("Unlock") {
                    unlockBackup()
                }
                .disabled(password.isEmpty || isImporting)
            }
        }
    }
    
    private func previewSection(_ preview: BackupPreview) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Backup Contents")
                    .font(.headline)
                
                Spacer()
                
                Image(systemName: "checkmark.seal.fill")
                    .foregroundColor(.green)
                Text("Verified")
                    .font(.caption)
                    .foregroundColor(.green)
            }
            
            VStack(alignment: .leading, spacing: 8) {
                detailRow(label: "Created", value: preview.createdAtFormatted)
                detailRow(label: "App Version", value: preview.appVersion)
                detailRow(label: "Wallets", value: "\(preview.walletCount)")
                
                if !preview.walletNames.isEmpty {
                    ForEach(preview.walletNames, id: \.self) { name in
                        HStack {
                            Text("•")
                                .foregroundColor(.secondary)
                            Text(name)
                                .font(.callout)
                        }
                        .padding(.leading, 80)
                    }
                }
                
                if preview.importedAccountCount > 0 {
                    detailRow(label: "Imported Accounts", value: "\(preview.importedAccountCount)")
                }
                
                detailRow(label: "Settings", value: preview.hasSettings ? "Included" : "Not included")
            }
            .padding()
            .background(Color.green.opacity(0.05))
            .cornerRadius(8)
        }
    }
    
    private func detailRow(label: String, value: String) -> some View {
        HStack {
            Text(label)
                .foregroundColor(.secondary)
                .frame(width: 120, alignment: .leading)
            Text(value)
        }
        .font(.callout)
    }
    
    private var optionsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Import Options")
                .font(.headline)
            
            Toggle(isOn: $overwriteExisting) {
                VStack(alignment: .leading) {
                    Text("Overwrite Existing Wallets")
                    Text("Replace wallets that already exist with backup versions")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
        }
    }
    
    private var importButton: some View {
        Button(action: importBackup) {
            HStack {
                if isImporting {
                    ProgressView()
                        .scaleEffect(0.8)
                        .padding(.trailing, 4)
                } else {
                    Image(systemName: "arrow.up.doc.fill")
                }
                Text(isImporting ? "Importing..." : "Import Backup")
            }
            .frame(maxWidth: .infinity)
            .padding()
            .background(preview != nil ? Color.blue : Color.gray)
            .foregroundColor(.white)
            .cornerRadius(10)
        }
        .buttonStyle(.plain)
        .disabled(preview == nil || isImporting)
    }
    
    private var statusMessages: some View {
        Group {
            if let summary = restorationSummary {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Image(systemName: summary.isSuccess ? "checkmark.circle.fill" : "exclamationmark.circle.fill")
                            .foregroundColor(summary.isSuccess ? .green : .orange)
                        Text(summary.isSuccess ? "Import Complete" : "Import Completed with Issues")
                            .font(.headline)
                            .foregroundColor(summary.isSuccess ? .green : .orange)
                    }
                    
                    Text(summary.summary)
                        .font(.callout)
                        .foregroundColor(.secondary)
                    
                    if !summary.failedWallets.isEmpty {
                        ForEach(summary.failedWallets, id: \.name) { failed in
                            Text("Failed: \(failed.name) - \(failed.error)")
                                .font(.caption)
                                .foregroundColor(.red)
                        }
                    }
                }
                .padding()
                .background(summary.isSuccess ? Color.green.opacity(0.1) : Color.orange.opacity(0.1))
                .cornerRadius(8)
            }
            
            if let error = importError {
                HStack {
                    Image(systemName: "exclamationmark.circle.fill")
                        .foregroundColor(.red)
                    Text(error)
                        .foregroundColor(.red)
                }
            }
        }
    }
    
    private func handleFileSelection(_ result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            if let url = urls.first {
                selectedFileURL = url
                preview = nil
                password = ""
                importError = nil
                restorationSummary = nil
            }
        case .failure(let error):
            if (error as NSError).code != NSUserCancelledError {
                importError = error.localizedDescription
            }
        }
    }
    
    private func unlockBackup() {
        guard let url = selectedFileURL else { return }
        
        isImporting = true
        importError = nil
        
        Task {
            do {
                // Start accessing security-scoped resource
                let accessing = url.startAccessingSecurityScopedResource()
                defer {
                    if accessing {
                        url.stopAccessingSecurityScopedResource()
                    }
                }
                
                let data = try Data(contentsOf: url)
                let backupPreview = try decoder.preview(data: data, password: password)
                
                await MainActor.run {
                    preview = backupPreview
                    isImporting = false
                }
            } catch {
                await MainActor.run {
                    importError = error.localizedDescription
                    isImporting = false
                }
            }
        }
    }
    
    private func importBackup() {
        guard let url = selectedFileURL else { return }
        
        isImporting = true
        importError = nil
        
        Task {
            do {
                let accessing = url.startAccessingSecurityScopedResource()
                defer {
                    if accessing {
                        url.stopAccessingSecurityScopedResource()
                    }
                }
                
                let data = try Data(contentsOf: url)
                let payload = try decoder.decode(data: data, password: password)
                let summary = try await decoder.restore(
                    payload: payload,
                    into: walletManager,
                    overwriteExisting: overwriteExisting
                )
                
                await MainActor.run {
                    restorationSummary = summary
                    isImporting = false
                    // Clear sensitive data
                    password = ""
                }
            } catch {
                await MainActor.run {
                    importError = error.localizedDescription
                    isImporting = false
                }
            }
        }
    }
}

// MARK: - Preview

#if DEBUG
struct BackupRestoreView_Previews: PreviewProvider {
    static var previews: some View {
        BackupRestoreView()
    }
}
#endif
