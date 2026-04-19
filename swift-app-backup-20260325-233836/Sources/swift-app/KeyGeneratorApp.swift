import SwiftUI

@main
struct KeyGeneratorApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @StateObject private var passcodeManager = PasscodeManager.shared
    @StateObject private var navigationCommands = NavigationCommandsManager.shared
    
    init() {
        ColdStartTimer.shared.markInit()
        print("Hawala Wallet Starting...")
        // Register custom fonts
        ClashGrotesk.registerFont()
        
        // ROADMAP-19 #5: Check for interrupted key generation on launch
        if EdgeCaseGuards.wasKeyGenerationInterrupted {
            print("⚠️ Previous key generation was interrupted — will prompt re-generation")
            EdgeCaseGuards.markKeyGenerationFinished()
        }
        
        // ROADMAP-19 #49: Check for interrupted backup
        if let step = EdgeCaseGuards.interruptedBackupStep {
            print("⚠️ Previous backup was interrupted at step: \(step) — will prompt resume")
            EdgeCaseGuards.markBackupFinished()
        }
    }
    
    var body: some Scene {
        WindowGroup {
            AppRootView()
                .environmentObject(passcodeManager)
                .environmentObject(navigationCommands)
                .withTheme()  // Apply theme settings (dark/light/system)
                .highContrastAware()  // ROADMAP-14 E11: Swap tokens when Increase Contrast is on
                .handlesExternalEvents(preferring: ["main"], allowing: ["main"]) // ROADMAP-19 #52: Prevent duplicate windows
        }
        .handlesExternalEvents(matching: ["main"]) // ROADMAP-19 #52: Route to existing window
        .windowStyle(.titleBar) // ROADMAP-13 E15: Native title bar for dynamic titles
        .commands {
            // ROADMAP-03: Global keyboard shortcuts
            HawalaCommands(navigationCommands: navigationCommands)
        }
    }
}

// MARK: - Hawala Menu Commands (ROADMAP-03)
/// Custom menu commands with keyboard shortcuts
struct HawalaCommands: Commands {
    @ObservedObject var navigationCommands: NavigationCommandsManager
    
    var body: some Commands {
        // Replace the standard Preferences menu item
        CommandGroup(replacing: .appSettings) {
            Button("Settings...") {
                navigationCommands.openSettings()
            }
            .keyboardShortcut(",", modifiers: .command)
        }
        
        // File menu additions
        CommandGroup(after: .newItem) {
            Button("New Transaction") {
                navigationCommands.newTransaction()
            }
            .keyboardShortcut("n", modifiers: .command)
            
            Button("Receive") {
                navigationCommands.receive()
            }
            .keyboardShortcut("r", modifiers: [.command, .shift])
            
            Divider()
        }
        
        // View menu additions
        CommandGroup(after: .toolbar) {
            Button("Refresh") {
                navigationCommands.refresh()
            }
            .keyboardShortcut("r", modifiers: .command)
            
            Button("Toggle History") {
                navigationCommands.toggleHistory()
            }
            .keyboardShortcut("h", modifiers: .command)
            
            Divider()
        }
        
        // Help menu additions
        CommandGroup(replacing: .help) {
            Button("Keyboard Shortcuts") {
                navigationCommands.showHelp()
            }
            .keyboardShortcut("/", modifiers: [.command, .shift])
            
            Divider()
            
            Button("Hawala Help") {
                // Open help documentation
                if let url = URL(string: "https://hawala.wallet/help") {
                    #if os(macOS)
                    NSWorkspace.shared.open(url)
                    #endif
                }
            }
        }
    }
}

/// Root view that handles passcode lock/unlock flow
struct AppRootView: View {
    @EnvironmentObject var passcodeManager: PasscodeManager
    @State private var hasCheckedPasscode = false
    @State private var rustHealthFailed = false
    
    var body: some View {
        ZStack {
            // Main app content
            ContentView()
                .opacity(passcodeManager.isLocked ? 0 : 1)
            
            // ROADMAP-01: Rust FFI health failure banner
            if rustHealthFailed {
                VStack {
                    HStack(spacing: 10) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundColor(.white)
                        Text("Wallet core unavailable. Signing and key generation may fail.")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundColor(.white)
                        Spacer()
                        Button(action: {
                            // Retry health check
                            let ok = RustService.shared.performHealthCheck()
                            if ok { rustHealthFailed = false }
                        }) {
                            Text("Retry")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundColor(.white)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 4)
                                .background(Capsule().fill(Color.white.opacity(0.2)))
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(12)
                    .background(Color.red.opacity(0.85))
                    Spacer()
                }
                .zIndex(200)
            }
            
            // Passcode setup prompt (first launch)
            if passcodeManager.showSetupPrompt && hasCheckedPasscode {
                PasscodeSetupScreen(
                    onComplete: {
                        passcodeManager.showSetupPrompt = false
                    },
                    onSkip: {
                        passcodeManager.skipPasscodeSetup()
                    }
                )
                .transition(.opacity)
                .zIndex(100)
            }
            
            // Passcode lock screen
            if passcodeManager.isLocked && passcodeManager.hasPasscode && hasCheckedPasscode {
                PasscodeLockScreen(onUnlock: {})
                    .transition(.opacity)
                    .zIndex(101)
            }
        }
        .animation(.easeInOut(duration: 0.3), value: passcodeManager.isLocked)
        .animation(.easeInOut(duration: 0.3), value: passcodeManager.showSetupPrompt)
        .onAppear {
            ColdStartTimer.shared.markRendered()
            
            // Small delay to let app initialize
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                passcodeManager.checkPasscodeStatus()
                hasCheckedPasscode = true
            }
            // ROADMAP-01: Check Rust health after launch
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                rustHealthFailed = !RustService.shared.isHealthy
            }
            
            // ROADMAP-11: Prioritized startup boot sequence
            Task { @MainActor in
                await StartupSequenceManager.shared.run()
                ColdStartTimer.shared.markReady()
            }
        }
    }
}

class AppDelegate: NSObject, NSApplicationDelegate {
    // ROADMAP-13 E8: Window state restoration keys
    private static let windowFrameKey = "hawala.windowFrame"
    
    func applicationDidFinishLaunching(_ notification: Notification) {
        // CRITICAL: Set activation policy to regular to appear in dock and receive keyboard input
        NSApplication.shared.setActivationPolicy(.regular)
        
        // ROADMAP-20: Track app launch
        AnalyticsService.shared.track(AnalyticsService.EventName.appLaunch)
        
        if let window = NSApplication.shared.windows.first {
            // ROADMAP-13 E8: Restore saved window frame
            restoreWindowFrame(window)
            window.makeKeyAndOrderFront(nil)
            NSApplication.shared.activate(ignoringOtherApps: true)
            
            // ROADMAP-13: Show native traffic lights for true macOS feel
            window.titlebarAppearsTransparent = true
            window.titleVisibility = .visible
            window.isMovableByWindowBackground = true
        }
        
        // ROADMAP-11: Start memory pressure monitoring
        _ = MemoryPressureHandler.shared
        
        // ROADMAP-11: Register startup boot tasks by priority
        let boot = StartupSequenceManager.shared
        
        boot.register(phase: .critical) {
            // Rust FFI health — must pass before signing/key ops
            let ok = RustService.shared.performHealthCheck()
            if !ok {
                print("⚠️ WARNING: Rust FFI health check failed — \(RustService.shared.healthCheckError ?? "unknown")")
            }
        }
        
        boot.register(phase: .high) {
            // Live price WebSocket
            WebSocketPriceService.shared.connect()
        }
        
        boot.register(phase: .normal) {
            // Background sync
            BackendSyncService.shared.startAutoSync(interval: 60)
        }
        
        boot.register(phase: .normal) {
            // Notification price alerts
            NotificationManager.shared.startPriceMonitoring()
        }
    }
    
    // ROADMAP-03: Deep link URL handling
    func application(_ application: NSApplication, open urls: [URL]) {
        for url in urls {
            if url.scheme == "hawala" {
                Task { @MainActor in
                    NavigationRouter.shared.handleDeepLink(url)
                }
            }
        }
    }
    
    func applicationWillTerminate(_ notification: Notification) {
        // ROADMAP-13 E8: Save window frame before quit
        // Clean up network services
        Task { @MainActor in
            if let window = NSApplication.shared.windows.first {
                saveWindowFrame(window)
            }
            WebSocketPriceService.shared.disconnect()
            BackendSyncService.shared.stopAutoSync()
            NotificationManager.shared.stopPriceMonitoring()
        }
    }
    
    // Also save when window resizes/moves (covers Cmd+Q and crash scenarios)
    func applicationDidResignActive(_ notification: Notification) {
        Task { @MainActor in
            if let window = NSApplication.shared.windows.first {
                saveWindowFrame(window)
            }
        }
    }
    
    // MARK: - ROADMAP-13 E8: Window Frame Persistence
    
    @MainActor
    private func saveWindowFrame(_ window: NSWindow) {
        let frame = window.frame
        let dict: [String: Double] = [
            "x": frame.origin.x,
            "y": frame.origin.y,
            "w": frame.size.width,
            "h": frame.size.height
        ]
        UserDefaults.standard.set(dict, forKey: Self.windowFrameKey)
    }
    
    @MainActor
    private func restoreWindowFrame(_ window: NSWindow) {
        guard let dict = UserDefaults.standard.dictionary(forKey: Self.windowFrameKey) as? [String: Double],
              let x = dict["x"], let y = dict["y"],
              let w = dict["w"], let h = dict["h"] else { return }
        
        let savedFrame = NSRect(x: x, y: y, width: max(w, 900), height: max(h, 600))
        
        // Verify the saved frame is visible on a connected screen
        let isOnScreen = NSScreen.screens.contains { screen in
            screen.visibleFrame.intersects(savedFrame)
        }
        
        if isOnScreen {
            window.setFrame(savedFrame, display: true, animate: false)
        } else {
            // Saved position is offscreen (display disconnected) — center on main
            if let mainScreen = NSScreen.main {
                let centered = NSRect(
                    x: mainScreen.visibleFrame.midX - savedFrame.width / 2,
                    y: mainScreen.visibleFrame.midY - savedFrame.height / 2,
                    width: savedFrame.width,
                    height: savedFrame.height
                )
                window.setFrame(centered, display: true, animate: false)
            }
        }
    }
}
