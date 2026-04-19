import Testing
@testable import swift_app

@Suite
struct SwiftAppTests {
    @Test func testAppStructLoads() {
        #expect(KeyGeneratorApp.self != nil)
    }
}
