import Testing
import SwiftUI
import CryptoKit
#if canImport(AppKit)
import AppKit
#endif
#if canImport(UIKit)
import UIKit
#endif
@testable import swift_app

@MainActor
@Suite
struct ContentViewSnapshotTests {
    @Test func testOnboardingSnapshotStable() throws {
        guard SnapshotRenderer.isSupported else {
            print("Skipping: Snapshot rendering not supported on this platform")
            return
        }
        let hash = try SnapshotRenderer.hash(for: ContentView(), size: CGSize(width: 800, height: 600), colorScheme: .light)
    #expect(hash == "d7f5adcdec82129ec29aab46876fc3e1cb9a1aa79c768d3086f5a49e9cd50072", "Update expected hash when intentional UI changes occur.")
    }
}

enum SnapshotRenderer {
    enum SnapshotError: Error {
        case rendererUnavailable
        case encodingFailed
        case unsupportedPlatform
    }

    static var isSupported: Bool {
        if #available(macOS 13.0, iOS 16.0, *) {
            #if canImport(AppKit) || canImport(UIKit)
            return true
            #else
            return false
            #endif
        }
        return false
    }

    @MainActor
    static func hash<V: View>(for view: V, size: CGSize, colorScheme: ColorScheme) throws -> String {
        let data = try render(view: view, size: size, colorScheme: colorScheme)
        let digest = SHA256.hash(data: data)
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    @MainActor
    private static func render<V: View>(view: V, size: CGSize, colorScheme: ColorScheme) throws -> Data {
        guard isSupported else { throw SnapshotError.unsupportedPlatform }
        if #available(macOS 13.0, iOS 16.0, *) {
            let content = view
                .frame(width: size.width, height: size.height)
                .environment(\.colorScheme, colorScheme)
            let renderer = ImageRenderer(content: content)
            renderer.scale = 1
            renderer.proposedSize = ProposedViewSize(width: size.width, height: size.height)
        #if canImport(AppKit)
            guard let nsImage = renderer.nsImage else {
                throw SnapshotError.rendererUnavailable
            }
            guard
                let tiff = nsImage.tiffRepresentation,
                let bitmap = NSBitmapImageRep(data: tiff),
                let png = bitmap.representation(using: .png, properties: [:])
            else {
                throw SnapshotError.encodingFailed
            }
            return png
        #elseif canImport(UIKit)
            guard let uiImage = renderer.uiImage, let png = uiImage.pngData() else {
                throw SnapshotError.encodingFailed
            }
            return png
        #else
            throw SnapshotError.unsupportedPlatform
        #endif
        } else {
            throw SnapshotError.unsupportedPlatform
        }
    }
}
