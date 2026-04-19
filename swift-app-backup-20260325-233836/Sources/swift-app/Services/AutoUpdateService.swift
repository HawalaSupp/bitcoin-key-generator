import Foundation

// MARK: - Auto-Update Service
// This service provides the foundation for Sparkle integration
// When Sparkle is added to Package.swift, this service will handle update checks

/// Manages application updates using Sparkle framework
/// Note: Sparkle must be added to Package.swift for full functionality
@MainActor
final class AutoUpdateService: ObservableObject {
    
    static let shared = AutoUpdateService()
    
    // MARK: - Published State
    
    @Published private(set) var isCheckingForUpdates = false
    @Published private(set) var updateAvailable: UpdateInfo?
    @Published private(set) var lastCheckDate: Date?
    @Published private(set) var error: UpdateError?
    
    // MARK: - Configuration
    
    /// The URL of the appcast.xml file
    static let feedURL = URL(string: "https://updates.hawala.app/appcast.xml")!
    
    /// How often to check for updates (in seconds)
    static let checkInterval: TimeInterval = 24 * 60 * 60 // 24 hours
    
    // MARK: - Types
    
    struct UpdateInfo: Identifiable {
        let id = UUID()
        let version: String
        let releaseNotes: String
        let downloadURL: URL
        let isCritical: Bool
        let minimumSystemVersion: String?
    }
    
    enum UpdateError: LocalizedError {
        case sparkleNotIntegrated
        case networkError(Error)
        case signatureVerificationFailed
        case downloadFailed
        
        var errorDescription: String? {
            switch self {
            case .sparkleNotIntegrated:
                return "Auto-update is not yet configured. Please check for updates manually."
            case .networkError(let error):
                return "Network error: \(error.localizedDescription)"
            case .signatureVerificationFailed:
                return "Update signature verification failed. The update may be compromised."
            case .downloadFailed:
                return "Failed to download update."
            }
        }
    }
    
    // MARK: - Initialization
    
    private init() {
        // When Sparkle is integrated, initialize SUUpdater here
        // For now, this is a placeholder
    }
    
    // MARK: - Public API
    
    /// Check for updates manually
    /// Returns immediately with a placeholder message until Sparkle is integrated
    func checkForUpdates() async {
        isCheckingForUpdates = true
        error = nil
        
        defer { isCheckingForUpdates = false }
        
        // Placeholder until Sparkle is integrated
        // When Sparkle is added to Package.swift, replace this with:
        // updaterController.updater.checkForUpdates()
        
        #if DEBUG
        // In debug, simulate update check
        try? await Task.sleep(nanoseconds: 500_000_000) // 0.5 seconds
        lastCheckDate = Date()
        
        // For testing, uncomment to simulate an available update:
        // updateAvailable = UpdateInfo(
        //     version: "1.0.1",
        //     releaseNotes: "Bug fixes and improvements",
        //     downloadURL: URL(string: "https://updates.hawala.app/Hawala-1.0.1.zip")!,
        //     isCritical: false,
        //     minimumSystemVersion: "13.0"
        // )
        #else
        // In release, note that Sparkle integration is pending
        error = .sparkleNotIntegrated
        #endif
    }
    
    /// Check if automatic update checks are enabled
    var automaticChecksEnabled: Bool {
        get { UserDefaults.standard.bool(forKey: "autoUpdateChecksEnabled") }
        set { UserDefaults.standard.set(newValue, forKey: "autoUpdateChecksEnabled") }
    }
    
    /// Schedule periodic update checks
    func schedulePeriodicChecks() {
        guard automaticChecksEnabled else { return }
        
        // When Sparkle is integrated, it handles this automatically
        // For now, this is a placeholder
        
        Task {
            // Check if enough time has passed since last check
            if let lastCheck = lastCheckDate,
               Date().timeIntervalSince(lastCheck) < Self.checkInterval {
                return
            }
            
            await checkForUpdates()
        }
    }
    
    /// Install available update
    func installUpdate() async {
        guard updateAvailable != nil else { return }
        
        // When Sparkle is integrated, this triggers the update installation
        // For now, open download page
        
        if let downloadURL = updateAvailable?.downloadURL {
            #if os(macOS)
            NSWorkspace.shared.open(downloadURL)
            #endif
        }
    }
    
    /// Dismiss available update notification
    func dismissUpdate() {
        updateAvailable = nil
    }
    
    /// Get current app version
    var currentVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0.0"
    }
    
    /// Get current build number
    var currentBuild: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "1"
    }
}

// MARK: - Sparkle Integration Placeholder

/*
 When Sparkle is integrated, update Package.swift:
 
 dependencies: [
     .package(url: "https://github.com/sparkle-project/Sparkle", from: "2.5.0"),
 ],
 
 And add to the target:
 
 .product(name: "Sparkle", package: "Sparkle"),
 
 Then replace the placeholder code above with:
 
 import Sparkle
 
 @MainActor
 final class AutoUpdateService: ObservableObject {
     static let shared = AutoUpdateService()
     
     private let updaterController: SPUStandardUpdaterController
     
     var updater: SPUUpdater {
         updaterController.updater
     }
     
     private init() {
         updaterController = SPUStandardUpdaterController(
             startingUpdater: true,
             updaterDelegate: nil,
             userDriverDelegate: nil
         )
     }
     
     func checkForUpdates() {
         updater.checkForUpdates()
     }
     
     var canCheckForUpdates: Bool {
         updater.canCheckForUpdates
     }
 }
 */

// MARK: - Update Notification View

import SwiftUI

/// A view that shows when an update is available
struct UpdateAvailableView: View {
    @ObservedObject var updateService = AutoUpdateService.shared
    
    var body: some View {
        if let update = updateService.updateAvailable {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Image(systemName: update.isCritical ? "exclamationmark.triangle.fill" : "arrow.down.circle.fill")
                        .font(.title2)
                        .foregroundColor(update.isCritical ? .red : .blue)
                    
                    VStack(alignment: .leading) {
                        Text(update.isCritical ? "Critical Update Available" : "Update Available")
                            .font(.headline)
                        Text("Version \(update.version)")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                    
                    Spacer()
                    
                    Button(action: { updateService.dismissUpdate() }) {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(.plain)
                }
                
                Text(update.releaseNotes)
                    .font(.body)
                    .foregroundColor(.secondary)
                
                HStack {
                    Button("Later") {
                        updateService.dismissUpdate()
                    }
                    .buttonStyle(.bordered)
                    
                    Button("Update Now") {
                        Task {
                            await updateService.installUpdate()
                        }
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
            .padding()
            .background(Color(.windowBackgroundColor))
            .cornerRadius(12)
            .shadow(radius: 5)
        }
    }
}

// MARK: - Check for Updates Menu Command

struct CheckForUpdatesCommand: View {
    @ObservedObject var updateService = AutoUpdateService.shared
    
    var body: some View {
        Button("Check for Updates…") {
            Task {
                await updateService.checkForUpdates()
            }
        }
        .disabled(updateService.isCheckingForUpdates)
    }
}
