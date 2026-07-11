import UniformTypeIdentifiers
import XCTest
import ImageViewCore
@testable import ImageViewApp

@MainActor
final class FileAssociationSettingsModelTests: XCTestCase {
    func testCommonAndExpandedFormatOrdering() {
        let model = makeModel()
        XCTAssertEqual(model.visibleFormats, [.jpeg, .png, .gif, .webp, .heic])

        model.setShowsAllFormats(true)

        XCTAssertEqual(model.visibleFormats, [
            .jpeg, .png, .gif, .webp, .heic,
            .tiff, .bmp, .heif, .avif, .svg
        ])
    }

    func testSelectCommonFormatsPreservesExtraSelections() {
        let model = makeModel()
        model.toggleSelection(for: .svg)

        model.selectCommonFormats()

        XCTAssertEqual(model.selectedFormats, Set([
            .jpeg, .png, .gif, .webp, .heic, .svg
        ]))
    }

    func testCollapsePreservesHiddenSelection() {
        let model = makeModel()
        model.setShowsAllFormats(true)
        model.toggleSelection(for: .avif)

        model.setShowsAllFormats(false)

        XCTAssertTrue(model.selectedFormats.contains(.avif))
    }

    func testRefreshReportsImageViewAndOtherApplicationNames() {
        let imageViewURL = URL(fileURLWithPath: "/Applications/ImageView.app")
        let previewURL = URL(fileURLWithPath: "/System/Applications/Preview.app")
        let service = DefaultApplicationServiceFake(defaults: [
            UTType.jpeg: imageViewURL,
            UTType.png: previewURL
        ])
        let model = makeModel(service: service, appURL: imageViewURL)

        model.refreshStatuses()

        XCTAssertEqual(model.rows[.jpeg]?.defaultApplicationName, "ImageView")
        XCTAssertTrue(model.rows[.jpeg]?.isImageViewDefault == true)
        XCTAssertEqual(model.rows[.png]?.defaultApplicationName, "Preview")
    }

    func testApplyChangesOnlySelectedFormatsAndClearsSuccesses() async {
        let service = DefaultApplicationServiceFake()
        let model = makeModel(service: service)
        model.toggleSelection(for: .jpeg)
        model.toggleSelection(for: .png)

        await model.applySelectedFormats()

        XCTAssertEqual(service.setTypes, [.jpeg, .png])
        XCTAssertTrue(model.selectedFormats.isEmpty)
        XCTAssertEqual(model.summary, .success(count: 2))
    }

    func testPartialFailureKeepsOnlyFailedFormatSelected() async {
        let service = DefaultApplicationServiceFake(failingTypes: [.png])
        let model = makeModel(service: service)
        model.toggleSelection(for: .jpeg)
        model.toggleSelection(for: .png)

        await model.applySelectedFormats()

        XCTAssertEqual(model.selectedFormats, [.png])
        XCTAssertEqual(model.summary, .partialSuccess(succeeded: 1, failed: 1))
        XCTAssertNotNil(model.rows[.png]?.errorDescription)
    }

    func testInvalidApplicationBundlePreventsMutation() async {
        let service = DefaultApplicationServiceFake()
        let model = makeModel(service: service, appURL: nil)
        model.toggleSelection(for: .gif)

        await model.applySelectedFormats()

        XCTAssertTrue(service.setTypes.isEmpty)
        XCTAssertEqual(model.summary, .invalidApplicationBundle)
        XCTAssertEqual(model.selectedFormats, [.gif])
    }
}

@MainActor
private final class DefaultApplicationServiceFake: DefaultApplicationServicing {
    var defaults: [UTType: URL]
    var failingTypes: Set<UTType>
    var setTypes: [UTType] = []

    init(defaults: [UTType: URL] = [:], failingTypes: Set<UTType> = []) {
        self.defaults = defaults
        self.failingTypes = failingTypes
    }

    func defaultApplicationURL(for contentType: UTType) -> URL? {
        defaults[contentType]
    }

    func setDefaultApplication(at applicationURL: URL, for contentType: UTType) async throws {
        setTypes.append(contentType)
        if failingTypes.contains(contentType) { throw TestFailure.denied }
        defaults[contentType] = applicationURL
    }
}

private enum TestFailure: LocalizedError {
    case denied
    var errorDescription: String? { "Denied" }
}

@MainActor
private func makeModel(
    service: DefaultApplicationServicing = DefaultApplicationServiceFake(),
    appURL: URL? = URL(fileURLWithPath: "/Applications/ImageView.app")
) -> FileAssociationSettingsModel {
    FileAssociationSettingsModel(service: service, applicationURL: { appURL })
}
