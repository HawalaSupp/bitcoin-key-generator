import Testing
import SwiftUI
@testable import swift_app

@Suite
struct AppearanceModeTests {
    @Test func testShortLabelsAreStable() {
        #expect(AppearanceMode.system.displayName == "System Default")
        #expect(AppearanceMode.light.displayName == "Light Mode")
        #expect(AppearanceMode.dark.displayName == "Dark Mode")
    }

    @Test func testColorSchemeMapping() {
        #expect(AppearanceMode.system.colorScheme == nil)
        #expect(AppearanceMode.light.colorScheme == .light)
        #expect(AppearanceMode.dark.colorScheme == .dark)
    }

    @Test func testMenuIconUniqueness() {
        let icons = AppearanceMode.allCases.map { $0.menuIconName }
        #expect(Set(icons).count == icons.count, "Each appearance mode should use a unique icon")
    }
}
