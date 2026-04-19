import Foundation
#if canImport(AppKit)
import AppKit
#endif
#if canImport(UIKit)
import UIKit
#endif

/// Manages clipboard operations with optional auto-clearing for sensitive data
@MainActor
final class ClipboardManager {
    static let shared = ClipboardManager()
    
    private var autoClearTask: Task<Void, Never>?
    private var lastCopiedValue: String?
    
    /// Default timeout for auto-clear (60 seconds)
    static let defaultClearTimeout: TimeInterval = 60
    
    private init() {}
    
    /// Copies text to clipboard
    func copy(_ text: String) {
#if canImport(AppKit)
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
#elseif canImport(UIKit)
        UIPasteboard.general.string = text
#endif
    }
    
    /// Copies sensitive text to clipboard with auto-clear after timeout
    /// - Parameters:
    ///   - text: The text to copy
    ///   - timeout: Time in seconds before the clipboard is cleared (default: 60)
    ///   - onClear: Optional callback when clipboard is cleared
    func copySensitive(_ text: String, timeout: TimeInterval = defaultClearTimeout, onClear: (() -> Void)? = nil) {
        // Cancel any existing auto-clear task
        autoClearTask?.cancel()
        
        // Copy the text
        copy(text)
        lastCopiedValue = text
        
        // Schedule auto-clear
        autoClearTask = Task { [weak self] in
            do {
                try await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000))
                
                // Only clear if the clipboard still contains our value
                guard let self = self else { return }
                if self.currentString() == self.lastCopiedValue {
                    self.clear()
                    self.lastCopiedValue = nil
                    onClear?()
                }
            } catch {
                // Task was cancelled
            }
        }
    }
    
    /// Clears the clipboard
    func clear() {
#if canImport(AppKit)
        NSPasteboard.general.clearContents()
#elseif canImport(UIKit)
        UIPasteboard.general.string = ""
#endif
    }
    
    /// Cancels any pending auto-clear task
    func cancelAutoClear() {
        autoClearTask?.cancel()
        autoClearTask = nil
        lastCopiedValue = nil
    }

    func currentString() -> String? {
#if canImport(AppKit)
        return NSPasteboard.general.string(forType: .string)
#elseif canImport(UIKit)
        return UIPasteboard.general.string
#endif
    }
}

/// Convenience wrapper for static-like access
enum ClipboardHelper {
    @MainActor
    static func copy(_ text: String) {
        ClipboardManager.shared.copy(text)
    }
    
    @MainActor
    static func copySensitive(_ text: String, timeout: TimeInterval = ClipboardManager.defaultClearTimeout, onClear: (() -> Void)? = nil) {
        ClipboardManager.shared.copySensitive(text, timeout: timeout, onClear: onClear)
    }
    
    @MainActor
    static func clear() {
        ClipboardManager.shared.clear()
    }
    
    @MainActor
    static func currentString() -> String? {
        ClipboardManager.shared.currentString()
    }
}
