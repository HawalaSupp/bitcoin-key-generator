import SwiftUI

@main
struct KeyGeneratorApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @StateObject private var passcodeManager = PasscodeManager.shared
    @StateObject private var navigationCommands = NavigationCommandsManager.shared
    
    init() {
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
    
    var body: some View {
        ZStack {
            // Main app content
            ContentView()
                .opacity(passcodeManager.isLocked ? 0 : 1)
            
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
            // Small delay to let app initialize
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                passcodeManager.checkPasscodeStatus()
                hasCheckedPasscode = true
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
        
        // Start network services
        Task { @MainActor in
            // Start WebSocket for live prices
            WebSocketPriceService.shared.connect()
            
            // Start background sync
            BackendSyncService.shared.startAutoSync(interval: 60)
            
            // Start notification price monitoring
            NotificationManager.shared.startPriceMonitoring()
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
