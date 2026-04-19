import SwiftUI
import UniformTypeIdentifiers

// MARK: - UTType Extension

extension UTType {
    static var hawalaBackup: UTType {
        UTType(exportedAs: "com.hawala.backup", conformingTo: .data)
    }
}

// MARK: - Password Strength

enum PasswordStrength {
    case weak
    case fair
    case good
    case strong
    
    var label: String {
        switch self {
        case .weak: return "Weak"
        case .fair: return "Fair"
        case .good: return "Good"
        case .strong: return "Strong"
        }
    }
    
    var color: Color {
        switch self {
        case .weak: return HawalaTheme.Colors.error
        case .fair: return HawalaTheme.Colors.warning
        case .good: return HawalaTheme.Colors.accent
        case .strong: return HawalaTheme.Colors.success
        }
    }
    
    var progress: CGFloat {
        switch self {
        case .weak: return 0.25
        case .fair: return 0.5
        case .good: return 0.75
        case .strong: return 1.0
        }
    }
    
    var isAcceptable: Bool {
        switch self {
        case .weak: return false
        default: return true
        }
    }
    
    static func evaluate(_ password: String) -> PasswordStrength {
        var score = 0
        
        // Length
        if password.count >= 8 { score += 1 }
        if password.count >= 12 { score += 1 }
        if password.count >= 16 { score += 1 }
        
        // Character types
        if password.rangeOfCharacter(from: .lowercaseLetters) != nil { score += 1 }
        if password.rangeOfCharacter(from: .uppercaseLetters) != nil { score += 1 }
        if password.rangeOfCharacter(from: .decimalDigits) != nil { score += 1 }
        if password.rangeOfCharacter(from: .punctuationCharacters) != nil { score += 1 }
        if password.rangeOfCharacter(from: .symbols) != nil { score += 1 }
        
        switch score {
        case 0...2: return .weak
        case 3...4: return .fair
        case 5...6: return .good
        default: return .strong
        }
    }
}

// MARK: - Hawala Backup Document

struct HawalaBackupDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.hawalaBackup] }
    
    var data: Data
    
    init(data: Data) {
        self.data = data
    }
    
    init(configuration: ReadConfiguration) throws {
        data = configuration.file.regularFileContents ?? Data()
    }
    
    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
    }
}

// MARK: - Backup Export View

/// View for exporting wallet backup
struct BackupExportView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var walletManager: WalletManager
    
    @State private var password = ""
    @State private var confirmPassword = ""
    @State private var isExporting = false
    @State private var exportError: String?
    @State private var showFileExporter = false
    @State private var backupData: Data?
    
    private var passwordsMatch: Bool {
        !password.isEmpty && password == confirmPassword
    }
    
    private var passwordStrength: PasswordStrength {
        PasswordStrength.evaluate(password)
    }
    
    private var dateString: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: Date())
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            headerView
            
            Divider()
            
            ScrollView {
                VStack(spacing: HawalaTheme.Spacing.xl) {
                    // Info banner
                    infoBanner
                    
                    // Password fields
                    passwordSection
                    
                    // Strength indicator
                    if !password.isEmpty {
                        strengthIndicator
                    }
                    
                    // Error message
                    if let error = exportError {
                        errorView(error)
                    }
                    
                    Spacer(minLength: HawalaTheme.Spacing.xl)
                    
                    // Export button
                    exportButton
                }
                .padding(HawalaTheme.Spacing.xl)
            }
        }
        .frame(width: 500, height: 550)
        .background(HawalaTheme.Colors.background)
        .fileExporter(
            isPresented: $showFileExporter,
            document: HawalaBackupDocument(data: backupData ?? Data()),
            contentType: .hawalaBackup,
            defaultFilename: "hawala-backup-\(dateString).hawala"
        ) { result in
            switch result {
            case .success(let url):
                ToastManager.shared.success("Backup Saved", message: "Saved to \(url.lastPathComponent)")
                dismiss()
            case .failure(let error):
                exportError = error.localizedDescription
            }
        }
    }
    
    // MARK: - Subviews
    
    private var headerView: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text("Export Backup")
                    .font(HawalaTheme.Typography.h2)
                    .foregroundStyle(HawalaTheme.Colors.textPrimary)
                
                Text("Create an encrypted backup file")
                    .font(HawalaTheme.Typography.caption)
                    .foregroundStyle(HawalaTheme.Colors.textSecondary)
            }
            
            Spacer()
            
            Button(action: { dismiss() }) {
                Image(systemName: "xmark.circle.fill")
                    .font(.title2)
                    .foregroundStyle(HawalaTheme.Colors.textSecondary)
            }
            .buttonStyle(.plain)
        }
        .padding(HawalaTheme.Spacing.lg)
    }
    
    private var infoBanner: some View {
        HStack(spacing: HawalaTheme.Spacing.md) {
            Image(systemName: "lock.shield.fill")
                .font(.title2)
                .foregroundStyle(HawalaTheme.Colors.accent)
            
            VStack(alignment: .leading, spacing: 4) {
                Text("Encrypted Backup")
                    .font(HawalaTheme.Typography.captionBold)
                    .foregroundStyle(HawalaTheme.Colors.textPrimary)
                
                Text("Your backup will be encrypted with AES-256. Choose a strong password you'll remember.")
                    .font(HawalaTheme.Typography.caption)
                    .foregroundStyle(HawalaTheme.Colors.textSecondary)
            }
            
            Spacer()
        }
        .padding(HawalaTheme.Spacing.md)
        .background(HawalaTheme.Colors.accent.opacity(0.1))
        .cornerRadius(HawalaTheme.Radius.md)
    }
    
    private var passwordSection: some View {
        VStack(alignment: .leading, spacing: HawalaTheme.Spacing.md) {
            Text("Encryption Password")
                .font(HawalaTheme.Typography.h4)
                .foregroundStyle(HawalaTheme.Colors.textPrimary)
            
            SecureField("Enter password", text: $password)
                .textFieldStyle(.roundedBorder)
            
            SecureField("Confirm password", text: $confirmPassword)
                .textFieldStyle(.roundedBorder)
            
            if !confirmPassword.isEmpty && !passwordsMatch {
                HStack {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(HawalaTheme.Colors.error)
                    Text("Passwords don't match")
                        .foregroundStyle(HawalaTheme.Colors.error)
                }
                .font(HawalaTheme.Typography.caption)
            }
        }
    }
    
    private var strengthIndicator: some View {
        VStack(alignment: .leading, spacing: HawalaTheme.Spacing.sm) {
            HStack {
                Text("Password Strength:")
                    .font(HawalaTheme.Typography.caption)
                    .foregroundStyle(HawalaTheme.Colors.textSecondary)
                
                Text(passwordStrength.label)
                    .font(HawalaTheme.Typography.caption)
                    .foregroundStyle(passwordStrength.color)
            }
            
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 2)
                        .fill(HawalaTheme.Colors.backgroundSecondary)
                        .frame(height: 4)
                    
                    RoundedRectangle(cornerRadius: 2)
                        .fill(passwordStrength.color)
                        .frame(width: geo.size.width * passwordStrength.progress, height: 4)
                }
            }
            .frame(height: 4)
        }
    }
    
    private func errorView(_ message: String) -> some View {
        HStack {
            Image(systemName: "exclamationmark.circle.fill")
                .foregroundStyle(HawalaTheme.Colors.error)
            Text(message)
                .foregroundStyle(HawalaTheme.Colors.error)
        }
        .font(HawalaTheme.Typography.body)
        .padding(HawalaTheme.Spacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(HawalaTheme.Colors.error.opacity(0.1))
        .cornerRadius(HawalaTheme.Radius.md)
    }
    
    private var exportButton: some View {
        Button {
            Task {
                await performExport()
            }
        } label: {
            HStack(spacing: HawalaTheme.Spacing.sm) {
                if isExporting {
                    ProgressView()
                        .controlSize(.small)
                } else {
                    Image(systemName: "square.and.arrow.up")
                }
                Text(isExporting ? "Encrypting..." : "Export Backup")
            }
            .font(HawalaTheme.Typography.captionBold)
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, HawalaTheme.Spacing.md)
            .background(
                passwordsMatch && passwordStrength.isAcceptable
                    ? HawalaTheme.Colors.accent
                    : HawalaTheme.Colors.textSecondary
            )
            .cornerRadius(HawalaTheme.Radius.md)
        }
        .buttonStyle(.plain)
        .disabled(!passwordsMatch || !passwordStrength.isAcceptable || isExporting)
    }
    
    // MARK: - Actions
    
    private func performExport() async {
        isExporting = true
        exportError = nil
        
        do {
            backupData = try await BackupManager.shared.exportBackup(
                password: password,
                walletManager: walletManager
            )
            showFileExporter = true
        } catch {
            exportError = error.localizedDescription
        }
        
        isExporting = false
    }
}

// MARK: - Backup Import View

struct BackupImportView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var walletManager: WalletManager
    
    @State private var password = ""
    @State private var isImporting = false
    @State private var importError: String?
    @State private var showFileImporter = false
    @State private var selectedFileURL: URL?
    @State private var importResult: ImportResult?
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            headerView
            
            Divider()
            
            VStack(spacing: HawalaTheme.Spacing.xl) {
                // File selection
                fileSelectionView
                
                // Password field (shown after file selected)
                if selectedFileURL != nil {
                    passwordSection
                }
                
                // Error or result
                if let error = importError {
                    errorView(error)
                }
                
                if let result = importResult {
                    resultView(result)
                }
                
                Spacer()
                
                // Import button
                if selectedFileURL != nil && importResult == nil {
                    importButton
                }
                
                if importResult != nil {
                    doneButton
                }
            }
            .padding(HawalaTheme.Spacing.xl)
        }
        .frame(width: 500, height: 500)
        .background(HawalaTheme.Colors.background)
        .fileImporter(
            isPresented: $showFileImporter,
            allowedContentTypes: [.hawalaBackup, .data],
            allowsMultipleSelection: false
        ) { result in
            switch result {
            case .success(let urls):
                if let url = urls.first {
                    selectedFileURL = url
                    importError = nil
                }
            case .failure(let error):
                importError = error.localizedDescription
            }
        }
    }
    
    // MARK: - Subviews
    
    private var headerView: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text("Import Backup")
                    .font(HawalaTheme.Typography.h2)
                    .foregroundStyle(HawalaTheme.Colors.textPrimary)
                
                Text("Restore from an encrypted backup file")
                    .font(HawalaTheme.Typography.caption)
                    .foregroundStyle(HawalaTheme.Colors.textSecondary)
            }
            
            Spacer()
            
            Button(action: { dismiss() }) {
                Image(systemName: "xmark.circle.fill")
                    .font(.title2)
                    .foregroundStyle(HawalaTheme.Colors.textSecondary)
            }
            .buttonStyle(.plain)
        }
        .padding(HawalaTheme.Spacing.lg)
    }
    
    private var fileSelectionView: some View {
        VStack(spacing: HawalaTheme.Spacing.md) {
            if let url = selectedFileURL {
                HStack {
                    Image(systemName: "doc.fill")
                        .font(.title2)
                        .foregroundStyle(HawalaTheme.Colors.accent)
                    
                    VStack(alignment: .leading) {
                        Text(url.lastPathComponent)
                            .font(HawalaTheme.Typography.body)
                            .foregroundStyle(HawalaTheme.Colors.textPrimary)
                        
                        Text("Ready to import")
                            .font(HawalaTheme.Typography.caption)
                            .foregroundStyle(HawalaTheme.Colors.textSecondary)
                    }
                    
                    Spacer()
                    
                    Button("Change") {
                        showFileImporter = true
                    }
                    .font(HawalaTheme.Typography.caption)
                }
                .padding(HawalaTheme.Spacing.md)
                .background(HawalaTheme.Colors.backgroundSecondary)
                .cornerRadius(HawalaTheme.Radius.md)
            } else {
                Button {
                    showFileImporter = true
                } label: {
                    VStack(spacing: HawalaTheme.Spacing.md) {
                        Image(systemName: "square.and.arrow.down")
                            .font(.system(size: 40))
                            .foregroundStyle(HawalaTheme.Colors.accent)
                        
                        Text("Select Backup File")
                            .font(HawalaTheme.Typography.body)
                            .foregroundStyle(HawalaTheme.Colors.textPrimary)
                        
                        Text(".hawala encrypted backup")
                            .font(HawalaTheme.Typography.caption)
                            .foregroundStyle(HawalaTheme.Colors.textSecondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, HawalaTheme.Spacing.xxl)
                    .background(HawalaTheme.Colors.backgroundSecondary)
                    .cornerRadius(HawalaTheme.Radius.lg)
                    .overlay(
                        RoundedRectangle(cornerRadius: HawalaTheme.Radius.lg)
                            .strokeBorder(style: StrokeStyle(lineWidth: 2, dash: [8]))
                            .foregroundStyle(HawalaTheme.Colors.textSecondary.opacity(0.5))
                    )
                }
                .buttonStyle(.plain)
            }
        }
    }
    
    private var passwordSection: some View {
        VStack(alignment: .leading, spacing: HawalaTheme.Spacing.md) {
            Text("Backup Password")
                .font(HawalaTheme.Typography.h4)
                .foregroundStyle(HawalaTheme.Colors.textPrimary)
            
            SecureField("Enter the password used during export", text: $password)
                .textFieldStyle(.roundedBorder)
        }
    }
    
    private func errorView(_ message: String) -> some View {
        HStack {
            Image(systemName: "exclamationmark.circle.fill")
                .foregroundStyle(HawalaTheme.Colors.error)
            Text(message)
                .foregroundStyle(HawalaTheme.Colors.error)
        }
        .font(HawalaTheme.Typography.body)
        .padding(HawalaTheme.Spacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(HawalaTheme.Colors.error.opacity(0.1))
        .cornerRadius(HawalaTheme.Radius.md)
    }
    
    private func resultView(_ result: ImportResult) -> some View {
        VStack(spacing: HawalaTheme.Spacing.md) {
            Image(systemName: result.hasErrors ? "exclamationmark.circle.fill" : "checkmark.circle.fill")
                .font(.system(size: 48))
                .foregroundStyle(result.hasErrors ? HawalaTheme.Colors.warning : HawalaTheme.Colors.success)
            
            Text(result.hasErrors ? "Import Completed with Warnings" : "Import Successful")
                .font(HawalaTheme.Typography.h3)
                .foregroundStyle(HawalaTheme.Colors.textPrimary)
            
            Text(result.summary)
                .font(HawalaTheme.Typography.body)
                .foregroundStyle(HawalaTheme.Colors.textSecondary)
            
            if result.hasErrors {
                ForEach(result.errors, id: \.self) { error in
                    Text("• \(error)")
                        .font(HawalaTheme.Typography.caption)
                        .foregroundStyle(HawalaTheme.Colors.error)
                }
            }
        }
        .padding(HawalaTheme.Spacing.lg)
    }
    
    private var importButton: some View {
        Button {
            Task {
                await performImport()
            }
        } label: {
            HStack(spacing: HawalaTheme.Spacing.sm) {
                if isImporting {
                    ProgressView()
                        .controlSize(.small)
                } else {
                    Image(systemName: "square.and.arrow.down")
                }
                Text(isImporting ? "Importing..." : "Import Backup")
            }
            .font(HawalaTheme.Typography.captionBold)
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, HawalaTheme.Spacing.md)
            .background(password.isEmpty ? HawalaTheme.Colors.textSecondary : HawalaTheme.Colors.accent)
            .cornerRadius(HawalaTheme.Radius.md)
        }
        .buttonStyle(.plain)
        .disabled(password.isEmpty || isImporting)
    }
    
    private var doneButton: some View {
        Button {
            dismiss()
        } label: {
            Text("Done")
                .font(HawalaTheme.Typography.captionBold)
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, HawalaTheme.Spacing.md)
                .background(HawalaTheme.Colors.accent)
                .cornerRadius(HawalaTheme.Radius.md)
        }
        .buttonStyle(.plain)
    }
    
    // MARK: - Actions
    
    private func performImport() async {
        guard let url = selectedFileURL else { return }
        
        isImporting = true
        importError = nil
        
        // Get security-scoped access
        guard url.startAccessingSecurityScopedResource() else {
            importError = "Cannot access the selected file"
            isImporting = false
            return
        }
        defer { url.stopAccessingSecurityScopedResource() }
        
        do {
            importResult = try await BackupManager.shared.importFromFile(
                at: url,
                password: password,
                walletManager: walletManager
            )
        } catch {
            importError = error.localizedDescription
        }
        
        isImporting = false
    }
}

// MARK: - Preview

#if false // Disabled #Preview for command-line builds
#if false
#if false
#Preview("Export") {
    BackupExportView(walletManager: WalletManager.shared)
}
#endif
#endif
#endif

#if false // Disabled #Preview for command-line builds
#if false
#if false
#Preview("Import") {
    BackupImportView(walletManager: WalletManager.shared)
}
#endif
#endif
#endif
