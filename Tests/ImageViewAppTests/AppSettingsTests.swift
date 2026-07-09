import XCTest
@testable import ImageViewApp

@MainActor
final class AppSettingsTests: XCTestCase {
    func testDefaultsFavorPreviewLikeSafetyAndHiddenFilmstrip() {
        let defaults = makeIsolatedDefaults()
        let settings = AppSettings(defaults: defaults)

        XCTAssertFalse(settings.pinsHUD)
        XCTAssertFalse(settings.showsFilmstrip)
        XCTAssertTrue(settings.confirmsDelete)
        XCTAssertTrue(settings.usesBlackFullscreenBackground)
    }

    func testSettingsPersistAcrossInstances() {
        let defaults = makeIsolatedDefaults()
        let first = AppSettings(defaults: defaults)
        first.pinsHUD = true
        first.showsFilmstrip = true
        first.confirmsDelete = false
        first.usesBlackFullscreenBackground = false

        let second = AppSettings(defaults: defaults)
        XCTAssertTrue(second.pinsHUD)
        XCTAssertTrue(second.showsFilmstrip)
        XCTAssertFalse(second.confirmsDelete)
        XCTAssertFalse(second.usesBlackFullscreenBackground)
    }

    private func makeIsolatedDefaults() -> UserDefaults {
        let suiteName = "ImageViewAppTests.AppSettings.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        return defaults
    }
}
