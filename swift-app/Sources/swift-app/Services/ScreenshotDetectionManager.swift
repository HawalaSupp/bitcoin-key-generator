import Foundation
import Combine
#if canImport(AppKit)
import AppKit
#endif

// MARK: - Screenshot Detection Manager
/// Monitors for screenshot and screen recording attempts on macOS
/// Provides warnings when sensitive data is visible

@MainActor
final class ScreenshotDetectionManager: ObservableObject {
    
    // MARK: - Published State
    @Published private(set) var isScreenBeingCaptured = false
    @Published private(set) var lastScreenshotDetected: Date?
    @Published var showScreenshotWarning = false
    
    // MARK: - Private State
    private var observers: [NSObjectProtocol] = []
    private var screenCaptureTimer: Timer?
    private var cancellables = Set<AnyCancellable>()
    
    // MARK: - Callbacks
    var onScreenshotDetected: (() -> Void)?
    var onScreenRecordingStarted: (() -> Void)?
    var onScreenRecordingStopped: (() -> Void)?
    
    // MARK: - Singleton
    static let shared = ScreenshotDetectionManager()
    
    private init() {
        setupObservers()
    }
    
    func cleanup() {
        observers.forEach { NotificationCenter.default.removeObserver($0) }
        screenCaptureTimer?.invalidate()
    }
    
    // MARK: - Setup
    
    private func setupObservers() {
        #if canImport(AppKit)
        // Monitor for screenshot notifications (Command+Shift+3, Command+Shift+4)
        // Note: macOS doesn't provide a direct notification, so we use file system monitoring
        setupScreenshotFolderMonitoring()
        
        // Monitor for screen recording/sharing
        startScreenCaptureMonitoring()
        #endif
    }
    
    #if canImport(AppKit)
    private func setupScreenshotFolderMonitoring() {
        // Default screenshot location
        let desktopPath = NSSearchPathForDirectoriesInDomains(.desktopDirectory, .userDomainMask, true).first ?? ""
        
        // Also check user's custom screenshot location
        let customLocation = UserDefaults.standard.persistentDomain(forName: "com.apple.screencapture")?["location"] as? String
        
        let paths = [desktopPath, customLocation].compactMap { $0 }
        
        for path in paths {
            let url = URL(fileURLWithPath: path)
            monitorDirectory(at: url)
        }
    }
    
    private func monitorDirectory(at url: URL) {
        let fileDescriptor = open(url.path, O_EVTONLY)
        guard fileDescriptor >= 0 else { return }
        
        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fileDescriptor,
            eventMask: .write,
            queue: .main
        )
        
        source.setEventHandler { [weak self] in
            self?.checkForNewScreenshots(in: url)
        }
        
        source.setCancelHandler {
            close(fileDescriptor)
        }
        
        source.resume()
    }
    
    private func checkForNewScreenshots(in directory: URL) {
        let fileManager = FileManager.default
        
        guard let contents = try? fileManager.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.creationDateKey],
            options: [.skipsHiddenFiles]
        ) else { return }
        
        let recentThreshold = Date().addingTimeInterval(-2) // Last 2 seconds
        
        for fileURL in contents {
            // Check if it's a screenshot file
            let filename = fileURL.lastPathComponent.lowercased()
            guard filename.contains("screenshot") || filename.contains("screen shot") else { continue }
            
            // Check if it's recent
            if let attributes = try? fileManager.attributesOfItem(atPath: fileURL.path),
               let creationDate = attributes[.creationDate] as? Date,
               creationDate > recentThreshold {
                
                Task { @MainActor in
                    self.handleScreenshotDetected()
                }
                break
            }
        }
    }
    
    private func startScreenCaptureMonitoring() {
        // Check screen capture status periodically
        screenCaptureTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.checkScreenCaptureStatus()
            }
        }
    }
    
    private func checkScreenCaptureStatus() {
        // Check if any window is being captured
        // This includes screen sharing, recording apps, etc.
        var isCapturing = false
        
        if let windowList = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as? [[String: Any]] {
            for window in windowList {
                if let ownerName = window[kCGWindowOwnerName as String] as? String {
                    // Known screen capture/recording apps
                    let captureApps = [
                        "QuickTime Player",
                        "OBS",
                        "ScreenFlow",
                        "Loom",
                        "Zoom",
                        "Microsoft Teams",
                        "Webex",
                        "Screen Sharing",
                        "screencaptureui"
                    ]
                    
                    if captureApps.contains(where: { ownerName.localizedCaseInsensitiveContains($0) }) {
                        isCapturing = true
                        break
                    }
                }
            }
        }
        
        // Also check CGDisplayStream for active recordings
        // Note: This is a simplified check; full detection would require more APIs
        
        let wasCapturing = isScreenBeingCaptured
        isScreenBeingCaptured = isCapturing
        
        if isCapturing && !wasCapturing {
            handleScreenRecordingStarted()
        } else if !isCapturing && wasCapturing {
            handleScreenRecordingStopped()
        }
    }
    #endif
    
    // MARK: - Event Handlers
    
    private func handleScreenshotDetected() {
        lastScreenshotDetected = Date()
        showScreenshotWarning = true
        onScreenshotDetected?()
        
        // Play warning sound
        #if canImport(AppKit)
        NSSound(named: "Basso")?.play()
        OnboardingHaptics.warning()
        #endif
        
        // Auto-dismiss warning after 5 seconds
        DispatchQueue.main.asyncAfter(deadline: .now() + 5) { [weak self] in
            self?.showScreenshotWarning = false
        }
        
        #if DEBUG
        print("📸 Screenshot detected!")
        #endif
    }
    
    private func handleScreenRecordingStarted() {
        showScreenshotWarning = true
        onScreenRecordingStarted?()
        
        #if canImport(AppKit)
        NSSound(named: "Basso")?.play()
        #endif
        
        #if DEBUG
        print("🔴 Screen recording started")
        #endif
    }
    
    private func handleScreenRecordingStopped() {
        showScreenshotWarning = false
        onScreenRecordingStopped?()
        
        #if DEBUG
        print("⚪ Screen recording stopped")
        #endif
    }
    
    // MARK: - Public API
    
    /// Temporarily hide sensitive content while showing
    /// Check if it's safe to display sensitive content
    var isSafeToShowSensitive: Bool {
        !isScreenBeingCaptured
    }
}

// MARK: - Notification Names

extension Notification.Name {
    static let hideSensitiveContent = Notification.Name("com.hawala.hideSensitiveContent")
    static let showSensitiveContent = Notification.Name("com.hawala.showSensitiveContent")
    static let screenshotDetected = Notification.Name("com.hawala.screenshotDetected")
}

// MARK: - Screenshot Warning View

import SwiftUI

struct ScreenshotWarningBanner: View {
    @ObservedObject var detector = ScreenshotDetectionManager.shared
    
    var body: some View {
        if detector.showScreenshotWarning {
            HStack(spacing: 12) {
                Image(systemName: detector.isScreenBeingCaptured ? "record.circle.fill" : "camera.fill")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(.white)
                
                VStack(alignment: .leading, spacing: 2) {
                    Text(detector.isScreenBeingCaptured ? "Screen Recording Active" : "Screenshot Detected")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(.white)
                    
                    Text(detector.isScreenBeingCaptured 
                         ? "Your screen is being recorded. Sensitive data may be visible."
                         : "A screenshot was just taken. Check if sensitive data was captured.")
                        .font(.system(size: 11))
                        .foregroundColor(.white.opacity(0.8))
                }
                
                Spacer()
                
                Button {
                    detector.showScreenshotWarning = false
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 18))
                        .foregroundColor(.white.opacity(0.7))
                }
                .buttonStyle(.plain)
            }
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color.red.opacity(0.9))
            )
            .padding(.horizontal, 20)
            .transition(.move(edge: .top).combined(with: .opacity))
            .animation(.spring(response: 0.3, dampingFraction: 0.7), value: detector.showScreenshotWarning)
        }
    }
}

// MARK: - Sensitive Content Modifier

struct SensitiveContentModifier: ViewModifier {
    @ObservedObject var detector = ScreenshotDetectionManager.shared
    @State private var isHidden = false
    
    func body(content: Content) -> some View {
        ZStack {
            if isHidden || detector.isScreenBeingCaptured {
                // Blur sensitive content during screen capture
                content
                    .blur(radius: 20)
                    .overlay {
                        VStack(spacing: 8) {
                            Image(systemName: "eye.slash.fill")
                                .font(.system(size: 24))
                            Text("Content hidden for security")
                                .font(.system(size: 12, weight: .medium))
                        }
                        .foregroundColor(.white.opacity(0.6))
                    }
            } else {
                content
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .hideSensitiveContent)) { _ in
            isHidden = true
        }
        .onReceive(NotificationCenter.default.publisher(for: .showSensitiveContent)) { _ in
            isHidden = false
        }
    }
}

extension View {
    /// Mark content as sensitive - will be hidden during screen recording
    func sensitiveContent() -> some View {
        self.modifier(SensitiveContentModifier())
    }
}
