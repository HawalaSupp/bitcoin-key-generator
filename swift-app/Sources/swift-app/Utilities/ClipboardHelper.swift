import Foundation
#if canImport(AppKit)
import AppKit
#endif
#if canImport(UIKit)
import UIKit
#endif

enum ClipboardHelper {
    static func copy(_ text: String) {
#if canImport(AppKit)
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
#elseif canImport(UIKit)
        UIPasteboard.general.string = text
#endif
    }

#if canImport(AppKit)
    static func currentString() -> String? {
        NSPasteboard.general.string(forType: .string)
    }
#endif
}
