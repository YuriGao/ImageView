import AppKit
import ImageViewCore
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
        let generalButtons = ["showsFilmstrip", "showsInspector", "confirmsDelete", "navigationTransitions"].compactMap {
            controller.window?.contentView?.viewWithIdentifier("settings.\($0)") as? NSButton
        }
        XCTAssertEqual(generalButtons.map(\.title), ["显示胶片预览", "显示信息面板", "移到废纸篓前确认", "使用图像切换动画"])
    }

    func testShowAllRevealsExactlyTenFormats() throws {
        let controller = makeController(preferredLanguages: ["en"])
        let content = try XCTUnwrap(controller.window?.contentView)
        let button = try XCTUnwrap(content.viewWithIdentifier("fileAssociation.showAll") as? NSButton)

        button.performClick(nil)

        XCTAssertEqual(SupportedImageFormat.allCases.filter {
            content.viewWithIdentifier("fileAssociation.\($0.rawValue)") != nil
        }.count, 10)
    }

    func testSelectingFormatEnablesApplyAndRendersExtensionAndDefaultStatus() throws {
        let previewURL = URL(fileURLWithPath: "/System/Applications/Preview.app")
        let controller = makeController(
            preferredLanguages: ["en"],
            service: ControllerServiceFake(defaults: [.jpeg: previewURL])
        )
        controller.showWindow(nil)
        let content = try XCTUnwrap(controller.window?.contentView)
        let checkbox = try XCTUnwrap(content.viewWithIdentifier("fileAssociation.jpeg.checkbox") as? NSButton)
        let extensions = try XCTUnwrap(content.viewWithIdentifier("fileAssociation.jpeg.extensions") as? NSTextField)
        let status = try XCTUnwrap(content.viewWithIdentifier("fileAssociation.jpeg.status") as? NSTextField)
        let apply = try XCTUnwrap(content.viewWithIdentifier("fileAssociation.apply") as? NSButton)

        checkbox.performClick(nil)

        XCTAssertTrue(apply.isEnabled)
        XCTAssertEqual(extensions.stringValue, "JPG, JPEG")
        XCTAssertEqual(status.stringValue, "Default: Preview")
        XCTAssertEqual(status.textColor, .secondaryLabelColor)
    }

    func testApplyingDisablesMutationControlsAndUsesApplyingTitle() async throws {
        let service = ControllerServiceFake(suspendsSet: true)
        let controller = makeController(preferredLanguages: ["en"], service: service)
        let content = try XCTUnwrap(controller.window?.contentView)
        let checkbox = try XCTUnwrap(content.viewWithIdentifier("fileAssociation.jpeg.checkbox") as? NSButton)
        let apply = try XCTUnwrap(content.viewWithIdentifier("fileAssociation.apply") as? NSButton)
        let showAll = try XCTUnwrap(content.viewWithIdentifier("fileAssociation.showAll") as? NSButton)
        checkbox.performClick(nil)

        apply.performClick(nil)
        await service.waitUntilSetStarts()

        XCTAssertEqual(apply.title, "Setting defaults…")
        XCTAssertFalse(apply.isEnabled)
        XCTAssertFalse(checkbox.isEnabled)
        XCTAssertFalse(showAll.isEnabled)
        service.resumeSet()
    }

    func testFailedApplyRendersLocalizedErrorInRedOnCorrespondingRow() async throws {
        let service = ControllerServiceFake(setError: ControllerSetError.denied)
        let controller = makeController(preferredLanguages: ["zh-Hans"], service: service)
        let content = try XCTUnwrap(controller.window?.contentView)
        let checkbox = try XCTUnwrap(content.viewWithIdentifier("fileAssociation.jpeg.checkbox") as? NSButton)
        let status = try XCTUnwrap(content.viewWithIdentifier("fileAssociation.jpeg.status") as? NSTextField)
        let apply = try XCTUnwrap(content.viewWithIdentifier("fileAssociation.apply") as? NSButton)
        checkbox.performClick(nil)

        apply.performClick(nil)
        await service.waitUntilSetFinishes()
        for _ in 0..<100 where status.stringValue != ControllerSetError.denied.localizedDescription {
            await Task.yield()
        }

        XCTAssertEqual(status.stringValue, "设置默认应用被拒绝")
        XCTAssertEqual(status.textColor, .systemRed)
    }
}

@MainActor
private func makeController(
    preferredLanguages: [String],
    service: ControllerServiceFake = ControllerServiceFake()
) -> PreferencesWindowController {
    let suiteName = "PreferencesWindowControllerTests.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suiteName)!
    defaults.removePersistentDomain(forName: suiteName)
    return PreferencesWindowController(
        settings: AppSettings(defaults: defaults),
        defaultApplicationService: service,
        applicationURL: { URL(fileURLWithPath: "/Applications/ImageView.app") },
        preferredLanguages: preferredLanguages
    )
}

@MainActor
private final class ControllerServiceFake: DefaultApplicationServicing {
    private let defaults: [UTType: URL]
    private let suspendsSet: Bool
    private let setError: (any Error)?
    private var startedContinuation: CheckedContinuation<Void, Never>?
    private var finishedContinuation: CheckedContinuation<Void, Never>?
    private var setContinuation: CheckedContinuation<Void, Never>?
    private var didStart = false
    private var didFinish = false

    init(
        defaults: [UTType: URL] = [:],
        suspendsSet: Bool = false,
        setError: (any Error)? = nil
    ) {
        self.defaults = defaults
        self.suspendsSet = suspendsSet
        self.setError = setError
    }

    func defaultApplicationURL(for contentType: UTType) -> URL? { defaults[contentType] }

    func setDefaultApplication(at applicationURL: URL, for contentType: UTType) async throws {
        didStart = true
        startedContinuation?.resume()
        startedContinuation = nil
        if suspendsSet {
            await withCheckedContinuation { setContinuation = $0 }
        }
        didFinish = true
        finishedContinuation?.resume()
        finishedContinuation = nil
        if let setError { throw setError }
    }

    func waitUntilSetStarts() async {
        if didStart { return }
        await withCheckedContinuation { startedContinuation = $0 }
    }

    func resumeSet() {
        setContinuation?.resume()
        setContinuation = nil
    }

    func waitUntilSetFinishes() async {
        if didFinish { return }
        await withCheckedContinuation { finishedContinuation = $0 }
    }
}

private enum ControllerSetError: LocalizedError {
    case denied

    var errorDescription: String? { "设置默认应用被拒绝" }
}

private extension NSView {
    func viewWithIdentifier(_ rawValue: String) -> NSView? {
        if identifier?.rawValue == rawValue { return self }
        return subviews.lazy.compactMap { $0.viewWithIdentifier(rawValue) }.first
    }
}
