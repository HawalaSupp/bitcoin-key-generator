import SwiftUI

@main
struct KeyGeneratorApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @StateObject private var passcodeManager = PasscodeManager.shared
    
    init() {
        print("Hawala Wallet Starting...")
    }
    
    var body: some Scene {
        WindowGroup {
            AppRootView()
                .environmentObject(passcodeManager)
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
