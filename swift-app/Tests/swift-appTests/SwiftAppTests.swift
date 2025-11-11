import XCTest
@testable import swift_app

final class SwiftAppTests: XCTestCase {
    func testAppStructLoads() {
        _ = KeyGeneratorApp()
        XCTAssertTrue(true)
    }
}
