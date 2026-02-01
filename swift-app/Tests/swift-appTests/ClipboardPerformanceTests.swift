import Testing
import Foundation
@testable import swift_app

@MainActor
@Suite
struct ClipboardPerformanceTests {
    @Test func testClipboardCopyRoundTripPerformance() throws {
#if canImport(AppKit)
        // Performance measurement - simplified without XCTest metrics
        let payload = String(repeating: "HawalaClipboard", count: 2_000)
        let startTime = Date()
        for _ in 0..<10 {
            ClipboardHelper.copy(payload)
            #expect(ClipboardHelper.currentString() == payload)
        }
        let elapsed = Date().timeIntervalSince(startTime)
        #expect(elapsed < 1.0, "Clipboard operations should complete in under 1 second")
#else
        // Skip test on platforms without AppKit
        print("Skipping: Clipboard performance test requires AppKit pasteboard access")
#endif
    }
}
