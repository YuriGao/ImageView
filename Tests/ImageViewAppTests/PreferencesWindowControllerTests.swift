import AppKit
import UniformTypeIdentifiers
import XCTest
@testable import ImageViewApp

@MainActor
final class PreferencesWindowControllerTests: XCTestCase {
    func testSettingsWindowContainsCommonFormatsAndCollapsedExtras() throws {
        let controller = makeController(preferredLanguages: ["en"])
        let content = try XCTUnwrap(controller.window?.contentView)

        XCTAssertNotNil(content.viewWithIdentifier("fileAssociation.jpeg"))
        XCTAssertNotNil(content.viewWithIdentifier("fileAssociation.png"))
        XCTAssertNotNil(content.viewWithIdentifier("fileAssociation.gif"))
        XCTAssertNotNil(content.viewWithIdentifier("fileAssociation.webp"))
        XCTAssertNotNil(content.viewWithIdentifier("fileAssociation.heic"))
        XCTAssertNil(content.viewWithIdentifier("fileAssociation.svg"))
    }

    func testApplyButtonStartsDisabled() throws {
        let controller = makeController(preferredLanguages: ["en"])
        let button = try XCTUnwrap(
            controller.window?.contentView?.viewWithIdentifier("fileAssociation.apply") as? NSButton
        )
        XCTAssertFalse(button.isEnabled)
        XCTAssertEqual(button.title, "Set ImageView as Default")
    }

    func testChineseSettingsUseLocalizedFileAssociationCopy() throws {
        let controller = makeController(preferredLanguages: ["zh-Hans"])
        let title = try XCTUnwrap(
            controller.window?.contentView?.viewWithIdentifier("fileAssociation.title") as? NSTextField
        )
        XCTAssertEqual(title.stringValue, "文件关联")
    }
}

@MainActor
private func makeController(preferredLanguages: [String]) -> PreferencesWindowController {
    let suiteName = "PreferencesWindowControllerTests.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suiteName)!
    defaults.removePersistentDomain(forName: suiteName)
    return PreferencesWindowController(
        settings: AppSettings(defaults: defaults),
        defaultApplicationService: ControllerServiceFake(),
        applicationURL: { URL(fileURLWithPath: "/Applications/ImageView.app") },
        preferredLanguages: preferredLanguages
    )
}

@MainActor
private final class ControllerServiceFake: DefaultApplicationServicing {
    func defaultApplicationURL(for contentType: UTType) -> URL? { nil }
    func setDefaultApplication(at applicationURL: URL, for contentType: UTType) async throws {}
}

private extension NSView {
    func viewWithIdentifier(_ rawValue: String) -> NSView? {
        if identifier?.rawValue == rawValue { return self }
        return subviews.lazy.compactMap { $0.viewWithIdentifier(rawValue) }.first
    }
}
