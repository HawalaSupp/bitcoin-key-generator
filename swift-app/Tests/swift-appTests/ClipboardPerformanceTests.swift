import XCTest
@testable import swift_app

final class ClipboardPerformanceTests: XCTestCase {
    func testClipboardCopyRoundTripPerformance() throws {
#if canImport(AppKit)
        let payload = String(repeating: "HawalaClipboard", count: 2_000)
        measure(metrics: [XCTClockMetric(), XCTCPUMetric()]) {
            ClipboardHelper.copy(payload)
            XCTAssertEqual(ClipboardHelper.currentString(), payload)
        }
#else
        throw XCTSkip("Clipboard performance test requires AppKit pasteboard access")
#endif
    }
}
