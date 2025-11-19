import XCTest
import SwiftUI
@testable import swift_app

final class AppearanceModeTests: XCTestCase {
    func testShortLabelsAreStable() {
        XCTAssertEqual(AppearanceMode.system.shortLabel, "Auto")
        XCTAssertEqual(AppearanceMode.light.shortLabel, "Light")
        XCTAssertEqual(AppearanceMode.dark.shortLabel, "Dark")
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
