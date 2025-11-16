import XCTest
@testable import swift_app

final class SwiftAppTests: XCTestCase {
    func testAppStructLoads() {
        XCTAssertNotNil(KeyGeneratorApp.self)
    }
}
