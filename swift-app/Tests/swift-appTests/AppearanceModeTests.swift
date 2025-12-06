import XCTest
import SwiftUI
@testable import swift_app

final class AppearanceModeTests: XCTestCase {
    func testShortLabelsAreStable() {
        XCTAssertEqual(AppearanceMode.system.displayName, "System Default")
        XCTAssertEqual(AppearanceMode.light.displayName, "Light Mode")
        XCTAssertEqual(AppearanceMode.dark.displayName, "Dark Mode")
    }

    func testColorSchemeMapping() {
        XCTAssertNil(AppearanceMode.system.colorScheme)
        XCTAssertEqual(AppearanceMode.light.colorScheme, .light)
        XCTAssertEqual(AppearanceMode.dark.colorScheme, .dark)
    }

    func testMenuIconUniqueness() {
        let icons = AppearanceMode.allCases.map { $0.menuIconName }
        XCTAssertEqual(Set(icons).count, icons.count, "Each appearance mode should use a unique icon")
    }
}
