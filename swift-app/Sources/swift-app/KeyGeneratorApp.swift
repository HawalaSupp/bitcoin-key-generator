import SwiftUI

@main
struct KeyGeneratorApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    
    init() {
        print("696969")
        print("696969")
        print("696969")
    }
    
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}

class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
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
