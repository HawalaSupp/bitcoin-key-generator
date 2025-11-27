import Foundation
import CoreImage
#if canImport(AppKit)
import AppKit
import UniformTypeIdentifiers
#endif

struct QRCodeScanner {
    @MainActor
    static func scanText() -> String? {
        #if canImport(AppKit)
        guard let imageURL = presentImagePicker() else { return nil }
        return decodeText(from: imageURL)
        #else
        return nil
        #endif
    }

    #if canImport(AppKit)
    @MainActor
    private static func presentImagePicker() -> URL? {
        let panel = NSOpenPanel()
        panel.message = "Select a QR code image"
        panel.allowedContentTypes = [.png, .jpeg, .tiff, .bmp]
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.canChooseFiles = true
        panel.level = .floating
        let response = panel.runModal()
        guard response == .OK else { return nil }
        return panel.url
    }

    private static func decodeText(from url: URL) -> String? {
        guard let ciImage = CIImage(contentsOf: url) else { return nil }
        let context = CIContext()
        let options: [String: Any] = [CIDetectorAccuracy: CIDetectorAccuracyHigh]
        guard let detector = CIDetector(ofType: CIDetectorTypeQRCode, context: context, options: options) else {
            return nil
        }
        let features = detector.features(in: ciImage)
        for feature in features {
            if let qrFeature = feature as? CIQRCodeFeature, let message = qrFeature.messageString {
                return message.trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }
        return nil
    }
    #endif
}
