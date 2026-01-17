import SwiftUI
import AppKit
import CoreText

// MARK: - Custom Font Registration and Usage
// Supports Clash Grotesk Bold for main balance display

enum ClashGrotesk {
    static let fontName = "ClashGrotesk-Bold"
    static let fontFileName = "ClashGrotesk-Bold"
    static let fontExtension = "otf"
    
    /// Register the Clash Grotesk font from bundle
    static func registerFont() {
        // Try to find the font - first in module bundle (SwiftPM), then main bundle
        var fontURL: URL?
        
        // SwiftPM uses Bundle.module for resources
        #if SWIFT_PACKAGE
        fontURL = Bundle.module.url(forResource: fontFileName, withExtension: fontExtension)
        #endif
        
        // Fallback to main bundle
        if fontURL == nil {
            fontURL = Bundle.main.url(forResource: fontFileName, withExtension: fontExtension)
        }
        
        guard let url = fontURL else {
            print("⚠️ ClashGrotesk font file not found in bundle")
            return
        }
        
        var errorRef: Unmanaged<CFError>?
        if !CTFontManagerRegisterFontsForURL(url as CFURL, .process, &errorRef) {
            if let error = errorRef?.takeRetainedValue() {
                print("⚠️ Failed to register ClashGrotesk font: \(error)")
            }
        } else {
            print("✅ ClashGrotesk font registered successfully")
        }
    }
    
    /// Get the Clash Grotesk Bold font, with fallback to system font
    static func bold(size: CGFloat) -> Font {
        // First check if the font is available
        if let _ = NSFont(name: fontName, size: size) {
            return Font.custom(fontName, size: size)
        }
        // Fallback to system font bold if custom font not available
        return Font.system(size: size, weight: .bold, design: .rounded)
    }
    
    /// Get the Clash Grotesk Medium font (uses bold with smaller size as approximation)
    static func medium(size: CGFloat) -> Font {
        // Use the same bold font but can be used for medium weight styling
        if let _ = NSFont(name: fontName, size: size) {
            return Font.custom(fontName, size: size)
        }
        // Fallback to system font semibold
        return Font.system(size: size, weight: .semibold, design: .rounded)
    }
    
    /// Check if the font is available
    static var isAvailable: Bool {
        NSFont(name: fontName, size: 12) != nil
    }
}

// MARK: - SwiftUI Font Extension
extension Font {
    /// Clash Grotesk Bold font for main balance display
    static func clashGroteskBold(size: CGFloat) -> Font {
        ClashGrotesk.bold(size: size)
    }
    
    /// Clash Grotesk Medium font for secondary headings
    static func clashGroteskMedium(size: CGFloat) -> Font {
        ClashGrotesk.medium(size: size)
    }
}

// MARK: - View Extension for Balance Display
extension View {
    /// Apply the main balance font style (Clash Grotesk Bold)
    func mainBalanceFont(size: CGFloat = 56) -> some View {
        self.font(.clashGroteskBold(size: size))
    }
}
