import XCTest
@testable import ImageViewApp

@MainActor
final class AppSettingsTests: XCTestCase {
    func testDefaultsFavorPreviewLikeSafetyAndHiddenFilmstrip() {
        let defaults = makeIsolatedDefaults()
        let settings = AppSettings(defaults: defaults)

        XCTAssertFalse(settings.showsFilmstrip)
        XCTAssertFalse(settings.showsInspector)
        XCTAssertTrue(settings.confirmsDelete)
        XCTAssertTrue(settings.animatesNavigationTransitions)
    }

    func testSettingsPersistAcrossInstances() {
        let defaults = makeIsolatedDefaults()
        let first = AppSettings(defaults: defaults)
        first.showsFilmstrip = true
        first.showsInspector = true
        first.confirmsDelete = false
        first.animatesNavigationTransitions = false

        let second = AppSettings(defaults: defaults)
        XCTAssertTrue(second.showsFilmstrip)
        XCTAssertTrue(second.showsInspector)
        XCTAssertFalse(second.confirmsDelete)
        XCTAssertFalse(second.animatesNavigationTransitions)
    }

    func testAppearanceDefaultsToSystem() {
        XCTAssertEqual(AppSettings(defaults: makeIsolatedDefaults()).appearance, .system)
    }

    func testAppearancePersistsAcrossInstances() {
        let defaults = makeIsolatedDefaults()
        AppSettings(defaults: defaults).appearance = .dark

        XCTAssertEqual(AppSettings(defaults: defaults).appearance, .dark)
    }

    func testUnknownAppearanceFallsBackToSystem() {
        let defaults = makeIsolatedDefaults()
        defaults.set("sepia", forKey: "appearance")

        XCTAssertEqual(AppSettings(defaults: defaults).appearance, .system)
    }

    private func makeIsolatedDefaults() -> UserDefaults {
        let suiteName = "ImageViewAppTests.AppSettings.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        return defaults
    }
}
