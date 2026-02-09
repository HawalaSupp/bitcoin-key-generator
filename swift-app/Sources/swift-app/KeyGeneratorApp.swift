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
    }
    
    var body: some Scene {
        WindowGroup {
            AppRootView()
                .environmentObject(passcodeManager)
                .environmentObject(navigationCommands)
                .withTheme()  // Apply theme settings (dark/light/system)
        }
        .windowStyle(.hiddenTitleBar) // Hide the gray title bar
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
    func applicationDidFinishLaunching(_ notification: Notification) {
        // CRITICAL: Set activation policy to regular to appear in dock and receive keyboard input
        NSApplication.shared.setActivationPolicy(.regular)
        
        if let window = NSApplication.shared.windows.first {
            window.makeKeyAndOrderFront(nil)
            NSApplication.shared.activate(ignoringOtherApps: true)
            
            // Hide the standard traffic light buttons since we have custom ones
            window.standardWindowButton(.closeButton)?.isHidden = true
            window.standardWindowButton(.miniaturizeButton)?.isHidden = true
            window.standardWindowButton(.zoomButton)?.isHidden = true
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
        // Clean up network services
        Task { @MainActor in
            WebSocketPriceService.shared.disconnect()
            BackendSyncService.shared.stopAutoSync()
            NotificationManager.shared.stopPriceMonitoring()
        }
    }
}
