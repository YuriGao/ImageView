import CoreGraphics
import Foundation
import ImageIO
import ImageViewCore
import UniformTypeIdentifiers
import XCTest
@testable import ImageViewApp

@MainActor
final class ViewerViewModelTests: XCTestCase {
    func testOpenLoadsImageAndBuildsNavigationStateFromDirectory() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let firstURL = root.appendingPathComponent("a.png")
        let secondURL = root.appendingPathComponent("b.png")
        try makePNGData(width: 3, height: 2).write(to: firstURL)
        try makePNGData(width: 6, height: 4).write(to: secondURL)

        let viewModel = ViewerViewModel()

        await viewModel.open(url: secondURL)

        XCTAssertEqual(viewModel.navigationState?.items.map(\.url.lastPathComponent), ["a.png", "b.png"])
        XCTAssertEqual(viewModel.navigationState?.currentItem?.url.lastPathComponent, "b.png")
        XCTAssertEqual(viewModel.currentImage?.pixelSize, CGSize(width: 6, height: 4))
        XCTAssertEqual(viewModel.currentMetadata?.format, .png)
        XCTAssertEqual(viewModel.currentMetadata?.pixelWidth, 6)
        XCTAssertEqual(viewModel.currentMetadata?.pixelHeight, 4)
        XCTAssertNil(viewModel.errorMessage)
    }

    func testOpenSetsErrorMessageWhenImageCannotBeDecoded() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let brokenURL = root.appendingPathComponent("broken.png")
        try Data("not an image".utf8).write(to: brokenURL)

        let viewModel = ViewerViewModel()

        await viewModel.open(url: brokenURL)

        XCTAssertEqual(viewModel.errorMessage, "图片损坏或无法解码：broken.png")
        XCTAssertNil(viewModel.currentImage)
        XCTAssertNil(viewModel.currentMetadata)
    }

    func testOpenSetsErrorMessageWhenImageFormatIsUnsupported() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let unsupportedURL = root.appendingPathComponent("broken.txt")
        try Data("not an image".utf8).write(to: unsupportedURL)

        let viewModel = ViewerViewModel()

        await viewModel.open(url: unsupportedURL)

        XCTAssertEqual(viewModel.errorMessage, "不支持的图片格式：txt")
        XCTAssertNil(viewModel.currentImage)
        XCTAssertNil(viewModel.currentMetadata)
        XCTAssertNil(viewModel.navigationState)
    }

    func testOpenReportsOnlySuccessfullyDecodedURL() async throws {
        let goodURL = URL(fileURLWithPath: "/tmp/good.png")
        let badURL = URL(fileURLWithPath: "/tmp/bad.png")
        let image = try makeDecodedImage(width: 4, height: 3)
        let viewModel = ViewerViewModel(
            scanContainingDirectory: { url in [ImageItem(url: url, format: .png)] },
            decodeImageAtURL: { url, _ in
                guard url == goodURL else { throw ImageDecodeError.cannotDecodeImage }
                return image
            }
        )
        var openedURLs: [URL] = []
        viewModel.onSuccessfulOpen = { openedURLs.append($0) }

        await viewModel.open(url: goodURL)
        await viewModel.open(url: badURL)

        XCTAssertEqual(openedURLs, [goodURL])
    }

    func testOpenFailureClearsPreviouslyDisplayedImageAndNavigationState() async throws {
        let goodURL = URL(fileURLWithPath: "/tmp/good.png")
        let brokenURL = URL(fileURLWithPath: "/tmp/broken.png")
        let goodImage = try makeDecodedImage(width: 6, height: 4)
        let scanner = ControlledScanner { url in
            let format = try XCTUnwrap(SupportedImageFormat(fileExtension: url.pathExtension))
            return [ImageItem(url: url, format: format)]
        }
        let decoder = StubDecoder { url, _ in
            if url == goodURL {
                return goodImage
            }
            throw ImageDecodeError.cannotCreateSource
        }
        let viewModel = ViewerViewModel(
            scanContainingDirectory: scanner.scan(containing:),
            decodeImageAtURL: decoder.decode(url:format:)
        )

        await viewModel.open(url: goodURL)
        XCTAssertEqual(viewModel.currentImage?.pixelSize, CGSize(width: 6, height: 4))
        XCTAssertEqual(viewModel.navigationState?.currentItem?.url, goodURL)

        await viewModel.open(url: brokenURL)

        XCTAssertEqual(viewModel.errorMessage, "图片损坏或无法解码：broken.png")
        XCTAssertNil(viewModel.currentImage)
        XCTAssertNil(viewModel.currentMetadata)
        XCTAssertNil(viewModel.navigationState)
    }

    func testOpenKeepsDecodedImageAndFallbackNavigationWhenScanFails() async throws {
        let url = URL(fileURLWithPath: "/tmp/lonely.png")
        let image = try makeDecodedImage(width: 8, height: 5)
        let scanner = ControlledScanner { _ in
            throw TestError.scanFailed
        }
        let decoder = StubDecoder { openedURL, _ in
            XCTAssertEqual(openedURL, url)
            return image
        }
        let viewModel = ViewerViewModel(
            scanContainingDirectory: scanner.scan(containing:),
            decodeImageAtURL: decoder.decode(url:format:)
        )

        await viewModel.open(url: url)

        XCTAssertEqual(viewModel.currentImage?.pixelSize, CGSize(width: 8, height: 5))
        XCTAssertEqual(viewModel.navigationState?.items.map(\.url), [url])
        XCTAssertEqual(viewModel.navigationState?.currentItem?.url, url)
        XCTAssertNil(viewModel.errorMessage)
    }

    func testOpenKeepsLatestRequestWhenEarlierDecodeFinishesLater() async throws {
        let firstURL = URL(fileURLWithPath: "/tmp/first.png")
        let secondURL = URL(fileURLWithPath: "/tmp/second.png")
        let firstImage = try makeDecodedImage(width: 3, height: 2)
        let secondImage = try makeDecodedImage(width: 9, height: 7)
        let scanner = ControlledScanner { url in
            let format = try XCTUnwrap(SupportedImageFormat(fileExtension: url.pathExtension))
            return [ImageItem(url: url, format: format)]
        }
        let loader = ControlledImageLoader(images: [
            firstURL: firstImage,
            secondURL: secondImage
        ])
        let viewModel = ViewerViewModel(
            scanContainingDirectory: scanner.scan(containing:),
            loadImageAtURL: loader.load(url:format:)
        )

        await loader.pauseNextLoad(for: firstURL)
        let firstOpen = Task { await viewModel.open(url: firstURL) }
        await loader.waitUntilPaused(url: firstURL)

        await viewModel.open(url: secondURL)
        try await loader.resume(url: firstURL)
        _ = await firstOpen.value

        XCTAssertEqual(viewModel.currentImage?.pixelSize, CGSize(width: 9, height: 7))
        XCTAssertEqual(viewModel.navigationState?.currentItem?.url, secondURL)
        XCTAssertNil(viewModel.errorMessage)
    }

    func testOpenDisplaysPreviewBeforeFullImageAndPublishesFullMetadata() async throws {
        let url = URL(fileURLWithPath: "/tmp/large.png")
        let preview = try makeDecodedImage(width: 2_048, height: 1_365)
        let full = try makeDecodedImage(width: 6_000, height: 4_000)
        let scanner = ControlledScanner { _ in [ImageItem(url: url, format: .png)] }
        let previewLoader = ControlledImageLoader(images: [url: preview])
        let fullLoader = ControlledImageLoader(images: [url: full])
        let viewModel = ViewerViewModel(
            scanContainingDirectory: scanner.scan(containing:),
            loadImageAtURL: fullLoader.load(url:format:),
            loadPreviewAtURL: previewLoader.load(url:format:)
        )

        await fullLoader.pauseNextLoad(for: url)
        let opening = Task { await viewModel.open(url: url) }
        await fullLoader.waitUntilPaused(url: url)
        await waitUntil { viewModel.currentImage?.pixelSize == CGSize(width: 2_048, height: 1_365) }

        XCTAssertNil(viewModel.currentMetadata)

        try await fullLoader.resume(url: url)
        _ = await opening.value

        XCTAssertEqual(viewModel.currentImage?.pixelSize, CGSize(width: 6_000, height: 4_000))
        XCTAssertEqual(viewModel.currentMetadata?.pixelWidth, 6_000)
    }

    func testPreviewCannotBeEditedBeforeFullImageArrives() async throws {
        let url = URL(fileURLWithPath: "/tmp/preview-edit-safety.png")
        let preview = try makeDecodedImage(width: 2_048, height: 1_365)
        let full = try makeDecodedImage(width: 6_000, height: 4_000)
        let previewLoader = ControlledImageLoader(images: [url: preview])
        let fullLoader = ControlledImageLoader(images: [url: full])
        let viewModel = ViewerViewModel(
            scanContainingDirectory: { _ in [ImageItem(url: url, format: .png)] },
            loadImageAtURL: fullLoader.load(url:format:),
            loadPreviewAtURL: previewLoader.load(url:format:)
        )

        await fullLoader.pauseNextLoad(for: url)
        let opening = Task { await viewModel.open(url: url) }
        await fullLoader.waitUntilPaused(url: url)
        await waitUntil { viewModel.currentImage?.pixelSize == preview.pixelSize }

        XCTAssertEqual(viewModel.loadPhase, .preview)
        viewModel.applyEdit(.rotateClockwise)
        XCTAssertFalse(viewModel.hasUnsavedEdits)
        XCTAssertEqual(viewModel.currentImage?.pixelSize, preview.pixelSize)

        try await fullLoader.resume(url: url)
        _ = await opening.value
    }

    func testOpenPublishesFullImageWithoutWaitingForSlowPreview() async throws {
        let url = URL(fileURLWithPath: "/tmp/full-wins-race.png")
        let preview = try makeDecodedImage(width: 2_048, height: 1_365)
        let full = try makeDecodedImage(width: 6_000, height: 4_000)
        let previewLoader = ControlledImageLoader(images: [url: preview])
        let fullLoader = ControlledImageLoader(images: [url: full])
        let viewModel = ViewerViewModel(
            scanContainingDirectory: { _ in [ImageItem(url: url, format: .png)] },
            loadImageAtURL: fullLoader.load(url:format:),
            loadPreviewAtURL: previewLoader.load(url:format:)
        )

        await previewLoader.pauseNextLoad(for: url)
        let opening = Task { await viewModel.open(url: url) }
        await previewLoader.waitUntilPaused(url: url)

        await waitUntil { viewModel.loadPhase == .full }
        XCTAssertEqual(viewModel.currentImage?.pixelSize, full.pixelSize)

        try await previewLoader.resume(url: url)
        _ = await opening.value
        XCTAssertEqual(viewModel.loadPhase, .full)
        XCTAssertEqual(viewModel.currentImage?.pixelSize, full.pixelSize)
    }

    func testNavigationInvalidatesOlderOpenBeforeItsFullImageArrives() async throws {
        let firstURL = URL(fileURLWithPath: "/tmp/open-race-first.png")
        let secondURL = URL(fileURLWithPath: "/tmp/open-race-second.png")
        let initialFirst = try makeDecodedImage(width: 1_000, height: 700)
        let staleFirst = try makeDecodedImage(width: 4_000, height: 2_800)
        let second = try makeDecodedImage(width: 2_000, height: 1_400)
        let fullLoader = SequencedImageLoader(plans: [
            firstURL: [
                .init(image: initialFirst),
                .init(image: staleFirst, pauseID: "stale-open")
            ],
            secondURL: [.init(image: second)]
        ])
        let previewLoader = ControlledImageLoader(images: [
            firstURL: initialFirst,
            secondURL: second
        ])
        let viewModel = ViewerViewModel(
            scanContainingDirectory: { _ in
                [ImageItem(url: firstURL, format: .png), ImageItem(url: secondURL, format: .png)]
            },
            loadImageAtURL: fullLoader.load(url:format:),
            loadPreviewAtURL: previewLoader.load(url:format:)
        )

        await viewModel.open(url: firstURL)
        let staleOpen = Task { await viewModel.open(url: firstURL) }
        await fullLoader.waitUntilPaused(id: "stale-open")

        viewModel.showNext()
        await waitUntil {
            viewModel.navigationState?.currentItem?.url == secondURL
                && viewModel.currentImage?.pixelSize == second.pixelSize
        }

        try await fullLoader.resume(id: "stale-open")
        _ = await staleOpen.value

        XCTAssertEqual(viewModel.navigationState?.currentItem?.url, secondURL)
        XCTAssertEqual(viewModel.currentImage?.pixelSize, second.pixelSize)
    }

    func testLatestDisplayRequestWinsAfterNavigatingAwayAndBackToSameURL() async throws {
        let firstURL = URL(fileURLWithPath: "/tmp/display-race-first.png")
        let secondURL = URL(fileURLWithPath: "/tmp/display-race-second.png")
        let initialFirst = try makeDecodedImage(width: 1_000, height: 700)
        let staleFirst = try makeDecodedImage(width: 4_000, height: 2_800)
        let latestFirst = try makeDecodedImage(width: 3_000, height: 2_100)
        let second = try makeDecodedImage(width: 2_000, height: 1_400)
        let fullLoader = SequencedImageLoader(plans: [
            firstURL: [
                .init(image: initialFirst),
                .init(image: staleFirst, pauseID: "stale-display"),
                .init(image: latestFirst)
            ],
            secondURL: [.init(image: second)]
        ])
        let viewModel = ViewerViewModel(
            scanContainingDirectory: { _ in
                [ImageItem(url: firstURL, format: .png), ImageItem(url: secondURL, format: .png)]
            },
            loadImageAtURL: fullLoader.load(url:format:),
            loadPreviewAtURL: { _, _ in initialFirst }
        )

        await viewModel.open(url: firstURL)
        let firstItem = try XCTUnwrap(viewModel.navigationState?.currentItem)
        viewModel.show(item: firstItem)
        await fullLoader.waitUntilPaused(id: "stale-display")

        viewModel.showNext()
        viewModel.showPrevious()
        await waitUntil { viewModel.currentImage?.pixelSize == latestFirst.pixelSize }

        try await fullLoader.resume(id: "stale-display")
        await fullLoader.waitUntilCompleted(id: "stale-display")
        await Task.yield()

        XCTAssertEqual(viewModel.navigationState?.currentItem?.url, firstURL)
        XCTAssertEqual(viewModel.currentImage?.pixelSize, latestFirst.pixelSize)
    }

    func testOpenCompletesScanningAndCallbackWithoutWaitingForCancelledPreview() async throws {
        let url = URL(fileURLWithPath: "/tmp/nonblocking-full.png")
        let preview = try makeDecodedImage(width: 2_048, height: 1_365)
        let full = try makeDecodedImage(width: 6_000, height: 4_000)
        let previewLoader = ControlledImageLoader(images: [url: preview])
        let fullLoader = ControlledImageLoader(images: [url: full])
        let scanCompleted = expectation(description: "directory scan and open callback completed")
        let viewModel = ViewerViewModel(
            scanContainingDirectory: { _ in [ImageItem(url: url, format: .png)] },
            loadImageAtURL: fullLoader.load(url:format:),
            loadPreviewAtURL: previewLoader.load(url:format:)
        )
        viewModel.onSuccessfulOpen = { openedURL in
            XCTAssertEqual(openedURL, url)
            scanCompleted.fulfill()
        }

        await previewLoader.pauseNextLoad(for: url)
        let opening = Task { await viewModel.open(url: url) }
        await previewLoader.waitUntilPaused(url: url)

        await fulfillment(of: [scanCompleted], timeout: 0.2)
        XCTAssertEqual(viewModel.loadPhase, .full)
        XCTAssertEqual(viewModel.currentImage?.pixelSize, full.pixelSize)

        try await previewLoader.resume(url: url)
        _ = await opening.value
    }

    func testPreviewCannotBeSavedInPlaceOrToAnotherURL() async throws {
        let url = URL(fileURLWithPath: "/tmp/preview-save-safety.png")
        let targetURL = URL(fileURLWithPath: "/tmp/preview-save-safety-copy.png")
        try? FileManager.default.removeItem(at: targetURL)
        defer { try? FileManager.default.removeItem(at: targetURL) }
        let preview = try makeDecodedImage(width: 2_048, height: 1_365)
        let full = try makeDecodedImage(width: 6_000, height: 4_000)
        let previewLoader = ControlledImageLoader(images: [url: preview])
        let fullLoader = ControlledImageLoader(images: [url: full])
        let viewModel = ViewerViewModel(
            scanContainingDirectory: { _ in [ImageItem(url: url, format: .png)] },
            loadImageAtURL: fullLoader.load(url:format:),
            loadPreviewAtURL: previewLoader.load(url:format:)
        )

        await fullLoader.pauseNextLoad(for: url)
        let opening = Task { await viewModel.open(url: url) }
        await fullLoader.waitUntilPaused(url: url)
        await waitUntil { viewModel.loadPhase == .preview }

        XCTAssertFalse(viewModel.saveCurrentEdits())
        XCTAssertFalse(viewModel.saveCurrentEdits(to: targetURL, format: .png))
        XCTAssertFalse(FileManager.default.fileExists(atPath: targetURL.path))
        XCTAssertFalse(viewModel.hasUnsavedEdits)
        XCTAssertEqual(viewModel.currentImage?.pixelSize, preview.pixelSize)

        try await fullLoader.resume(url: url)
        _ = await opening.value
    }

    func testNewOpenIgnoresLatePreviewFromEarlierRequest() async throws {
        let firstURL = URL(fileURLWithPath: "/tmp/first.png")
        let secondURL = URL(fileURLWithPath: "/tmp/second.png")
        let firstPreview = try makeDecodedImage(width: 800, height: 600)
        let firstFull = try makeDecodedImage(width: 4_000, height: 3_000)
        let secondPreview = try makeDecodedImage(width: 1_000, height: 750)
        let secondFull = try makeDecodedImage(width: 5_000, height: 3_750)
        let scanner = ControlledScanner { url in
            [ImageItem(url: url, format: .png)]
        }
        let previewLoader = ControlledImageLoader(images: [firstURL: firstPreview, secondURL: secondPreview])
        let fullLoader = ControlledImageLoader(images: [firstURL: firstFull, secondURL: secondFull])
        let viewModel = ViewerViewModel(
            scanContainingDirectory: scanner.scan(containing:),
            loadImageAtURL: fullLoader.load(url:format:),
            loadPreviewAtURL: previewLoader.load(url:format:)
        )

        await previewLoader.pauseNextLoad(for: firstURL)
        let firstOpen = Task { await viewModel.open(url: firstURL) }
        await previewLoader.waitUntilPaused(url: firstURL)

        await viewModel.open(url: secondURL)
        try await previewLoader.resume(url: firstURL)
        _ = await firstOpen.value

        XCTAssertEqual(viewModel.currentImage?.pixelSize, CGSize(width: 5_000, height: 3_750))
        XCTAssertEqual(viewModel.navigationState?.currentItem?.url, secondURL)
    }

    func testDisplayTitleTracksCurrentItemAcrossNavigationAndErrors() async throws {
        let firstURL = URL(fileURLWithPath: "/tmp/first.png")
        let secondURL = URL(fileURLWithPath: "/tmp/second.png")
        let brokenURL = URL(fileURLWithPath: "/tmp/broken.png")
        let image = try makeDecodedImage(width: 4, height: 3)
        let scanner = ControlledScanner { url in
            let format = try XCTUnwrap(SupportedImageFormat(fileExtension: url.pathExtension))
            if url == firstURL {
                return [
                    ImageItem(url: firstURL, format: format),
                    ImageItem(url: secondURL, format: format)
                ]
            }
            return [ImageItem(url: url, format: format)]
        }
        let decoder = StubDecoder { url, _ in
            if url == brokenURL {
                throw ImageDecodeError.cannotCreateSource
            }
            return image
        }
        let viewModel = ViewerViewModel(
            scanContainingDirectory: scanner.scan(containing:),
            decodeImageAtURL: decoder.decode(url:format:)
        )

        XCTAssertEqual(viewModel.displayTitle, "ImageView")

        await viewModel.open(url: firstURL)
        XCTAssertEqual(viewModel.displayTitle, "first.png")

        viewModel.showNext()
        await waitUntil { viewModel.displayTitle == "second.png" }
        XCTAssertEqual(viewModel.displayTitle, "second.png")

        await viewModel.open(url: brokenURL)
        XCTAssertEqual(viewModel.displayTitle, "ImageView")
    }

    func testDisplayTitleMarksUnsavedEdits() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let imageURL = root.appendingPathComponent("editable.png")
        try makePNGData(width: 5, height: 3).write(to: imageURL)
        let viewModel = ViewerViewModel()

        await viewModel.open(url: imageURL)
        XCTAssertEqual(viewModel.displayTitle, "editable.png")

        viewModel.applyEdit(.mirrorHorizontal)
        XCTAssertEqual(viewModel.displayTitle, "editable.png - Edited")

        XCTAssertTrue(viewModel.discardCurrentEdits())
        XCTAssertEqual(viewModel.displayTitle, "editable.png")
    }

    func testDisplayTitleFormattingAddsEditedMarkerOnlyWhenNeeded() {
        XCTAssertEqual(
            ViewerViewModel.displayTitle(filename: "image.png", hasUnsavedEdits: false),
            "image.png"
        )
        XCTAssertEqual(
            ViewerViewModel.displayTitle(filename: "image.png", hasUnsavedEdits: true),
            "image.png - Edited"
        )
    }

    func testNavigationTracksCurrentItemAndSelection() async throws {
        let firstURL = URL(fileURLWithPath: "/tmp/first.png")
        let secondURL = URL(fileURLWithPath: "/tmp/second.png")
        let image = try makeDecodedImage(width: 4, height: 3)
        let scanner = ControlledScanner { url in
            let format = try XCTUnwrap(SupportedImageFormat(fileExtension: url.pathExtension))
            return [
                ImageItem(url: firstURL, format: format),
                ImageItem(url: secondURL, format: format)
            ]
        }
        let decoder = StubDecoder { _, _ in image }
        let viewModel = ViewerViewModel(
            scanContainingDirectory: scanner.scan(containing:),
            decodeImageAtURL: decoder.decode(url:format:)
        )

        XCTAssertNil(viewModel.navigationState)

        await viewModel.open(url: firstURL)
        XCTAssertEqual(viewModel.currentFilename, "first.png")
        XCTAssertEqual(viewModel.navigationState?.currentIndex, 0)
        XCTAssertEqual(viewModel.navigationState?.items.count, 2)

        viewModel.showNext()
        await waitUntil { viewModel.navigationState?.currentItem?.url == secondURL }
        XCTAssertEqual(viewModel.currentFilename, "second.png")

        let selected = try XCTUnwrap(viewModel.navigationState?.items.first)
        viewModel.show(item: selected)
        await waitUntil { viewModel.navigationState?.currentItem?.url == firstURL }
        XCTAssertEqual(viewModel.currentFilename, "first.png")
    }

    func testMoveCurrentToTrashClearsDisplayedImageWhenLastItemIsRemoved() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let imageURL = root.appendingPathComponent("solo.png")
        try makePNGData(width: 5, height: 4).write(to: imageURL)
        let viewModel = ViewerViewModel(
            moveToTrashAtURL: { _ in }
        )

        await viewModel.open(url: imageURL)
        XCTAssertEqual(viewModel.displayTitle, "solo.png")
        XCTAssertNotNil(viewModel.currentImage)

        viewModel.moveCurrentToTrash()

        XCTAssertNil(viewModel.currentImage)
        XCTAssertNil(viewModel.currentMetadata)
        XCTAssertNil(viewModel.navigationState)
        XCTAssertEqual(viewModel.displayTitle, "ImageView")
        XCTAssertEqual(viewModel.errorMessage, "没有可显示的图片")
    }

    func testRenameCurrentSuccessClearsPriorErrorMessage() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let imageURL = root.appendingPathComponent("start.png")
        try makePNGData(width: 5, height: 4).write(to: imageURL)
        let viewModel = ViewerViewModel()

        await viewModel.open(url: imageURL)
        viewModel.renameCurrent(to: "   ")
        XCTAssertEqual(viewModel.errorMessage, "无法重命名：start.png")

        viewModel.renameCurrent(to: "renamed")

        XCTAssertEqual(viewModel.navigationState?.currentItem?.url.lastPathComponent, "renamed.png")
        XCTAssertNil(viewModel.errorMessage)
    }

    func testCanPreloadInBackgroundSkipsFallbackFormats() {
        XCTAssertTrue(ViewerViewModel.canPreloadInBackground(.png))
        XCTAssertTrue(ViewerViewModel.canPreloadInBackground(.jpeg))
        XCTAssertFalse(ViewerViewModel.canPreloadInBackground(.gif))
        XCTAssertFalse(ViewerViewModel.canPreloadInBackground(.svg))
        XCTAssertFalse(ViewerViewModel.canPreloadInBackground(.webp))
        XCTAssertFalse(ViewerViewModel.canPreloadInBackground(.avif))
    }

    func testFileVersionDetectsSameSizeRewriteWithRestoredModificationDate() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let url = root.appendingPathComponent("rewrite.png")
        let originalData = Data("original".utf8)
        let replacementData = Data("replaced".utf8)
        XCTAssertEqual(originalData.count, replacementData.count)
        try originalData.write(to: url)
        let originalDate = try XCTUnwrap(
            FileManager.default.attributesOfItem(atPath: url.path)[.modificationDate] as? Date
        )
        let originalVersion = try XCTUnwrap(CurrentFileVersion.read(at: url))

        let handle = try FileHandle(forWritingTo: url)
        try handle.write(contentsOf: replacementData)
        try handle.synchronize()
        try handle.close()
        try FileManager.default.setAttributes([.modificationDate: originalDate], ofItemAtPath: url.path)

        XCTAssertEqual(try Data(contentsOf: url), replacementData)
        XCTAssertNotEqual(CurrentFileVersion.read(at: url), originalVersion)
    }

    func testFileVersionDetectsAtomicReplacementWithSameSizeAndModificationDate() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let url = root.appendingPathComponent("replacement.png")
        let originalData = Data("original".utf8)
        let replacementData = Data("replaced".utf8)
        XCTAssertEqual(originalData.count, replacementData.count)
        try originalData.write(to: url)
        let originalDate = try XCTUnwrap(
            FileManager.default.attributesOfItem(atPath: url.path)[.modificationDate] as? Date
        )
        let originalVersion = try XCTUnwrap(CurrentFileVersion.read(at: url))

        try replacementData.write(to: url, options: .atomic)
        try FileManager.default.setAttributes([.modificationDate: originalDate], ofItemAtPath: url.path)

        XCTAssertEqual(try Data(contentsOf: url), replacementData)
        XCTAssertNotEqual(CurrentFileVersion.read(at: url), originalVersion)
    }

    func testNavigationRejectsCachedPixelsAfterSamePathFileReplacement() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let firstURL = root.appendingPathComponent("a.png")
        let secondURL = root.appendingPathComponent("b.png")
        var originalData = try makePNGData(width: 4, height: 3, fillColor: (1, 0, 0, 1))
        var replacementData = try makePNGData(width: 4, height: 3, fillColor: (0, 0, 1, 1))
        originalData.append(contentsOf: repeatElement(0, count: max(0, replacementData.count - originalData.count)))
        replacementData.append(contentsOf: repeatElement(0, count: max(0, originalData.count - replacementData.count)))
        XCTAssertEqual(originalData.count, replacementData.count)
        try originalData.write(to: firstURL)
        try makePNGData(width: 4, height: 3).write(to: secondURL)
        let originalModificationDate = try XCTUnwrap(
            FileManager.default.attributesOfItem(atPath: firstURL.path)[.modificationDate] as? Date
        )

        let viewModel = ViewerViewModel()
        await viewModel.open(url: firstURL)
        XCTAssertEqual(try rgbaPixel(in: XCTUnwrap(viewModel.currentImage?.cgImage)), [255, 0, 0, 255])

        await viewModel.open(url: secondURL)
        XCTAssertEqual(viewModel.navigationState?.currentItem?.url, secondURL)

        try replacementData.write(to: firstURL, options: .atomic)
        try FileManager.default.setAttributes([.modificationDate: originalModificationDate], ofItemAtPath: firstURL.path)

        await viewModel.open(url: firstURL)
        XCTAssertEqual(viewModel.navigationState?.currentItem?.url, firstURL)

        XCTAssertEqual(try rgbaPixel(in: XCTUnwrap(viewModel.currentImage?.cgImage)), [0, 0, 255, 255])
    }

    func testRefreshRemovesExternallyDeletedCurrentItemAndDisplaysNextImage() async throws {
        let deletedURL = URL(fileURLWithPath: "/tmp/a.png")
        let nextURL = URL(fileURLWithPath: "/tmp/b.png")
        let firstImage = try makeDecodedImage(width: 4, height: 3)
        let nextImage = try makeDecodedImage(width: 7, height: 5)
        let versions = FileVersionSequence(values: [
            deletedURL: [FileVersionSequence.initial, nil],
            nextURL: [FileVersionSequence.initial]
        ])
        let viewModel = ViewerViewModel(
            scanContainingDirectory: { _ in [
                ImageItem(url: deletedURL, format: .png),
                ImageItem(url: nextURL, format: .png)
            ] },
            decodeImageAtURL: { url, _ in url == deletedURL ? firstImage : nextImage },
            currentFileVersionAtURL: versions.value(for:)
        )

        await viewModel.open(url: deletedURL)
        await viewModel.refreshCurrentFileIfNeeded()

        XCTAssertEqual(viewModel.navigationState?.currentItem?.url, nextURL)
        await waitUntil { viewModel.currentImage?.pixelSize == CGSize(width: 7, height: 5) }
        XCTAssertEqual(viewModel.currentImage?.pixelSize, CGSize(width: 7, height: 5))
        XCTAssertEqual(viewModel.errorMessage, "文件已在外部移除：a.png")
    }

    func testRefreshReloadsCurrentImageWhenExternalVersionChanges() async throws {
        let url = URL(fileURLWithPath: "/tmp/replaced.png")
        let original = try makeDecodedImage(width: 4, height: 3)
        let replacement = try makeDecodedImage(width: 9, height: 6)
        let versions = FileVersionSequence(values: [url: [FileVersionSequence.initial, FileVersionSequence.replacement]])
        let decoder = DecodeSequence(images: [original, replacement])
        let viewModel = ViewerViewModel(
            scanContainingDirectory: { _ in [ImageItem(url: url, format: .svg)] },
            decodeImageAtURL: decoder.decode(url:format:),
            currentFileVersionAtURL: versions.value(for:)
        )

        await viewModel.open(url: url)
        await viewModel.refreshCurrentFileIfNeeded()

        XCTAssertEqual(viewModel.currentImage?.pixelSize, CGSize(width: 9, height: 6))
        XCTAssertEqual(viewModel.currentMetadata?.pixelWidth, 9)
        XCTAssertNil(viewModel.errorMessage)
    }

    func testRefreshShowsErrorAndKeepsNavigationWhenExternalReplacementCannotDecode() async throws {
        let firstURL = URL(fileURLWithPath: "/tmp/a.png")
        let secondURL = URL(fileURLWithPath: "/tmp/b.png")
        let image = try makeDecodedImage(width: 4, height: 3)
        let versions = FileVersionSequence(values: [
            firstURL: [FileVersionSequence.initial, FileVersionSequence.replacement],
            secondURL: [FileVersionSequence.initial]
        ])
        let viewModel = ViewerViewModel(
            scanContainingDirectory: { _ in [
                ImageItem(url: firstURL, format: .png),
                ImageItem(url: secondURL, format: .png)
            ] },
            decodeImageAtURL: { url, _ in
                if url == firstURL && versions.hasReadReplacement(for: url) {
                    throw ImageDecodeError.cannotCreateSource
                }
                return image
            },
            currentFileVersionAtURL: versions.value(for:)
        )

        await viewModel.open(url: firstURL)
        await viewModel.refreshCurrentFileIfNeeded()

        XCTAssertEqual(viewModel.navigationState?.currentItem?.url, firstURL)
        XCTAssertEqual(viewModel.currentImage?.pixelSize, CGSize(width: 4, height: 3))
        XCTAssertEqual(viewModel.errorMessage, "图片已在外部修改且无法解码：a.png")

        viewModel.showNext()
        await waitUntil { viewModel.navigationState?.currentItem?.url == secondURL }
        XCTAssertEqual(viewModel.currentImage?.pixelSize, CGSize(width: 4, height: 3))
    }

    func testRefreshDoesNotReplaceUnsavedEditsAfterExternalChange() async throws {
        let url = URL(fileURLWithPath: "/tmp/edited.png")
        let original = try makeDecodedImage(width: 4, height: 3)
        let replacement = try makeDecodedImage(width: 9, height: 6)
        let versions = FileVersionSequence(values: [url: [FileVersionSequence.initial, FileVersionSequence.replacement]])
        let decoder = DecodeSequence(images: [original, replacement])
        let viewModel = ViewerViewModel(
            scanContainingDirectory: { _ in [ImageItem(url: url, format: .svg)] },
            decodeImageAtURL: decoder.decode(url:format:),
            currentFileVersionAtURL: versions.value(for:)
        )

        await viewModel.open(url: url)
        viewModel.applyEdit(.rotateClockwise)
        await viewModel.refreshCurrentFileIfNeeded()

        XCTAssertTrue(viewModel.hasUnsavedEdits)
        XCTAssertEqual(viewModel.currentImage?.pixelSize, CGSize(width: 3, height: 4))
        XCTAssertEqual(viewModel.errorMessage, "图片已在外部修改：edited.png")
    }

    func testApplyEditMarksUnsavedAndUpdatesImageSize() async throws {
        let imageURL = try makeTemporaryPNG(width: 6, height: 4, name: "edit-source")
        defer { try? FileManager.default.removeItem(at: imageURL.deletingLastPathComponent()) }

        let viewModel = ViewerViewModel()
        await viewModel.open(url: imageURL)

        viewModel.applyEdit(.rotateClockwise)

        XCTAssertTrue(viewModel.hasUnsavedEdits)
        XCTAssertEqual(viewModel.currentImage?.pixelSize, CGSize(width: 4, height: 6))
        XCTAssertNil(viewModel.errorMessage)
    }

    func testCropMarksEditsAndDiscardRestoresOriginalSize() async throws {
        let imageURL = try makeTemporaryPNG(width: 5, height: 3, name: "crop-source")
        defer { try? FileManager.default.removeItem(at: imageURL.deletingLastPathComponent()) }

        let viewModel = ViewerViewModel()
        await viewModel.open(url: imageURL)

        viewModel.applyEdit(.crop(CGRect(x: 1, y: 1, width: 3, height: 2)))

        XCTAssertEqual(viewModel.currentImage?.pixelSize, CGSize(width: 3, height: 2))
        XCTAssertTrue(viewModel.hasUnsavedEdits)
        XCTAssertTrue(viewModel.discardCurrentEdits())
        XCTAssertEqual(viewModel.currentImage?.pixelSize, CGSize(width: 5, height: 3))
        XCTAssertFalse(viewModel.hasUnsavedEdits)
    }

    func testDiscardCurrentEditsReloadsCachedOriginalAndClearsUnsavedState() async throws {
        let imageURL = try makeTemporaryPNG(width: 7, height: 5, name: "discard-source")
        defer { try? FileManager.default.removeItem(at: imageURL.deletingLastPathComponent()) }

        let viewModel = ViewerViewModel()
        await viewModel.open(url: imageURL)

        viewModel.applyEdit(.rotateClockwise)
        XCTAssertEqual(viewModel.currentImage?.pixelSize, CGSize(width: 5, height: 7))

        viewModel.discardCurrentEditsAndReload()
        await waitUntil { viewModel.hasUnsavedEdits == false && viewModel.currentImage?.pixelSize == CGSize(width: 7, height: 5) }

        XCTAssertFalse(viewModel.hasUnsavedEdits)
        XCTAssertEqual(viewModel.currentImage?.pixelSize, CGSize(width: 7, height: 5))
        XCTAssertNil(viewModel.errorMessage)
    }

    func testSaveCurrentEditsClearsUnsavedStateForWritableFormats() async throws {
        let imageURL = try makeTemporaryPNG(width: 8, height: 3, name: "save-source")
        defer { try? FileManager.default.removeItem(at: imageURL.deletingLastPathComponent()) }

        let viewModel = ViewerViewModel()
        await viewModel.open(url: imageURL)

        viewModel.applyEdit(.rotateClockwise)
        XCTAssertTrue(viewModel.hasUnsavedEdits)

        XCTAssertTrue(viewModel.saveCurrentEdits())

        XCTAssertFalse(viewModel.hasUnsavedEdits)
        XCTAssertEqual(viewModel.currentImage?.pixelSize, CGSize(width: 3, height: 8))
        XCTAssertNil(viewModel.errorMessage)
    }

    func testSaveCurrentEditsInPlacePreservesSourceMetadata() async throws {
        let imageURL = try makeTemporaryMetadataJPEG(name: "metadata-in-place")
        defer { try? FileManager.default.removeItem(at: imageURL.deletingLastPathComponent()) }

        let viewModel = ViewerViewModel()
        await viewModel.open(url: imageURL)
        viewModel.applyEdit(.mirrorHorizontal)

        XCTAssertTrue(viewModel.saveCurrentEdits())

        let properties = try imageProperties(at: imageURL)
        let exif = try XCTUnwrap(properties[kCGImagePropertyExifDictionary] as? [CFString: Any])
        let tiff = try XCTUnwrap(properties[kCGImagePropertyTIFFDictionary] as? [CFString: Any])
        XCTAssertEqual((properties[kCGImagePropertyOrientation] as? NSNumber)?.intValue, 1)
        XCTAssertEqual(exif[kCGImagePropertyExifDateTimeOriginal] as? String, "2026:07:11 12:34:56")
        XCTAssertEqual(tiff[kCGImagePropertyTIFFMake] as? String, "ImageView Test")
        XCTAssertNotNil(properties[kCGImagePropertyGPSDictionary])
        XCTAssertEqual((properties[kCGImagePropertyPixelWidth] as? NSNumber)?.intValue, viewModel.currentImage?.cgImage.width)
        XCTAssertEqual((properties[kCGImagePropertyPixelHeight] as? NSNumber)?.intValue, viewModel.currentImage?.cgImage.height)
    }

    func testSaveCurrentEditsToNewURLUpdatesCurrentItem() async throws {
        let imageURL = try makeTemporaryPNG(width: 8, height: 3, name: "save-as-source")
        let targetURL = imageURL.deletingLastPathComponent().appendingPathComponent("save-as-target.png")
        defer { try? FileManager.default.removeItem(at: imageURL.deletingLastPathComponent()) }

        let viewModel = ViewerViewModel()
        await viewModel.open(url: imageURL)
        viewModel.applyEdit(.rotateClockwise)

        XCTAssertTrue(viewModel.saveCurrentEdits(to: targetURL, format: .png))
        XCTAssertEqual(viewModel.navigationState?.currentItem?.url, targetURL)
        XCTAssertFalse(viewModel.hasUnsavedEdits)
        XCTAssertEqual(viewModel.currentImage?.pixelSize, CGSize(width: 3, height: 8))
        XCTAssertTrue(FileManager.default.fileExists(atPath: targetURL.path))
    }

    func testSaveCurrentEditsToNewURLUsesCurrentItemAsMetadataSource() async throws {
        let imageURL = try makeTemporaryMetadataJPEG(name: "metadata-save-as-source")
        let targetURL = imageURL.deletingLastPathComponent().appendingPathComponent("metadata-save-as-target.jpg")
        defer { try? FileManager.default.removeItem(at: imageURL.deletingLastPathComponent()) }

        let viewModel = ViewerViewModel()
        await viewModel.open(url: imageURL)
        viewModel.applyEdit(.mirrorHorizontal)

        XCTAssertTrue(viewModel.saveCurrentEdits(to: targetURL, format: .jpeg))

        let properties = try imageProperties(at: targetURL)
        let exif = try XCTUnwrap(properties[kCGImagePropertyExifDictionary] as? [CFString: Any])
        let tiff = try XCTUnwrap(properties[kCGImagePropertyTIFFDictionary] as? [CFString: Any])
        XCTAssertEqual((properties[kCGImagePropertyOrientation] as? NSNumber)?.intValue, 1)
        XCTAssertEqual(exif[kCGImagePropertyExifDateTimeOriginal] as? String, "2026:07:11 12:34:56")
        XCTAssertEqual(tiff[kCGImagePropertyTIFFModel] as? String, "Metadata Fixture")
        XCTAssertNotNil(properties[kCGImagePropertyGPSDictionary])

        let originalProperties = try imageProperties(at: imageURL)
        XCTAssertEqual((originalProperties[kCGImagePropertyOrientation] as? NSNumber)?.intValue, 6)
    }

    func testSaveCurrentEditsShowsErrorForUnsupportedFormats() async throws {
        let svgURL = URL(fileURLWithPath: "/tmp/vector.svg")
        let image = try makeDecodedImage(width: 4, height: 2)
        let scanner = ControlledScanner { url in
            XCTAssertEqual(url, svgURL)
            return [ImageItem(url: svgURL, format: .svg)]
        }
        let decoder = StubDecoder { url, format in
            XCTAssertEqual(url, svgURL)
            XCTAssertEqual(format, .svg)
            return image
        }
        let viewModel = ViewerViewModel(
            scanContainingDirectory: scanner.scan(containing:),
            decodeImageAtURL: decoder.decode(url:format:)
        )

        await viewModel.open(url: svgURL)
        viewModel.applyEdit(.mirrorHorizontal)
        XCTAssertFalse(viewModel.saveCurrentEdits())

        XCTAssertTrue(viewModel.hasUnsavedEdits)
        XCTAssertEqual(viewModel.errorMessage, "无法保存该格式的编辑结果")
    }

    func testDiscardCurrentEditsRestoresOriginalImageAndClearsUnsavedState() async throws {
        let imageURL = try makeTemporaryPNG(width: 6, height: 4, name: "discard-in-place")
        defer { try? FileManager.default.removeItem(at: imageURL.deletingLastPathComponent()) }

        let viewModel = ViewerViewModel()
        await viewModel.open(url: imageURL)

        viewModel.applyEdit(.rotateClockwise)
        XCTAssertEqual(viewModel.currentImage?.pixelSize, CGSize(width: 4, height: 6))

        XCTAssertTrue(viewModel.discardCurrentEdits())

        XCTAssertFalse(viewModel.hasUnsavedEdits)
        XCTAssertEqual(viewModel.currentImage?.pixelSize, CGSize(width: 6, height: 4))
        XCTAssertNil(viewModel.errorMessage)
    }

    func testDiscardCurrentEditsAtNavigationBoundaryLeavesOriginalImageVisible() async throws {
        let firstURL = try makeTemporaryPNG(width: 6, height: 4, name: "boundary-first")
        let root = firstURL.deletingLastPathComponent()
        let secondURL = root.appendingPathComponent("boundary-second.png")
        defer { try? FileManager.default.removeItem(at: root) }
        try makePNGData(width: 8, height: 5).write(to: secondURL)

        let viewModel = ViewerViewModel()
        await viewModel.open(url: secondURL)

        viewModel.applyEdit(.rotateClockwise)
        XCTAssertEqual(viewModel.currentImage?.pixelSize, CGSize(width: 5, height: 8))
        XCTAssertEqual(viewModel.navigationState?.currentItem?.url, secondURL)

        XCTAssertTrue(viewModel.discardCurrentEdits())
        viewModel.showNext()
        await waitUntil { viewModel.hasUnsavedEdits == false && viewModel.navigationState?.currentItem?.url == secondURL }

        XCTAssertEqual(viewModel.currentImage?.pixelSize, CGSize(width: 8, height: 5))
        XCTAssertFalse(viewModel.hasUnsavedEdits)
        XCTAssertNil(viewModel.errorMessage)
    }

    private func makePNGData(
        width: Int,
        height: Int,
        fillColor: (red: CGFloat, green: CGFloat, blue: CGFloat, alpha: CGFloat) = (0.2, 0.4, 0.8, 1)
    ) throws -> Data {
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        guard let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            throw TestError.cannotCreateContext
        }

        context.setFillColor(
            red: fillColor.red,
            green: fillColor.green,
            blue: fillColor.blue,
            alpha: fillColor.alpha
        )
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))

        guard let image = context.makeImage(),
              let destinationData = CFDataCreateMutable(nil, 0),
              let destination = CGImageDestinationCreateWithData(destinationData, UTType.png.identifier as CFString, 1, nil) else {
            throw TestError.cannotEncodeImage
        }

        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else {
            throw TestError.cannotEncodeImage
        }

        return destinationData as Data
    }

    private func rgbaPixel(in image: CGImage) throws -> [UInt8] {
        var bytes = [UInt8](repeating: 0, count: 4)
        guard let context = CGContext(
            data: &bytes,
            width: 1,
            height: 1,
            bitsPerComponent: 8,
            bytesPerRow: 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            throw TestError.cannotCreateContext
        }
        context.interpolationQuality = .none
        context.draw(image, in: CGRect(x: 0, y: 0, width: 1, height: 1))
        return bytes
    }

    private func makeTemporaryPNG(width: Int, height: Int, name: String) throws -> URL {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let imageURL = root.appendingPathComponent("\(name).png")
        try makePNGData(width: width, height: height).write(to: imageURL)
        return imageURL
    }

    private func makeTemporaryMetadataJPEG(name: String) throws -> URL {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let imageURL = root.appendingPathComponent("\(name).jpg")
        try makeMetadataJPEGData().write(to: imageURL)
        return imageURL
    }

    private func makeMetadataJPEGData() throws -> Data {
        let decoded = try makeDecodedImage(width: 8, height: 3)
        guard let data = CFDataCreateMutable(nil, 0),
              let destination = CGImageDestinationCreateWithData(
                data,
                UTType.jpeg.identifier as CFString,
                1,
                nil
              ) else {
            throw TestError.cannotEncodeImage
        }
        let properties: [CFString: Any] = [
            kCGImagePropertyOrientation: 6,
            kCGImagePropertyExifDictionary: [
                kCGImagePropertyExifDateTimeOriginal: "2026:07:11 12:34:56"
            ],
            kCGImagePropertyTIFFDictionary: [
                kCGImagePropertyTIFFMake: "ImageView Test",
                kCGImagePropertyTIFFModel: "Metadata Fixture",
                kCGImagePropertyTIFFOrientation: 6
            ],
            kCGImagePropertyGPSDictionary: [
                kCGImagePropertyGPSLatitudeRef: "N",
                kCGImagePropertyGPSLatitude: 31.2304,
                kCGImagePropertyGPSLongitudeRef: "E",
                kCGImagePropertyGPSLongitude: 121.4737
            ]
        ]
        CGImageDestinationAddImage(destination, decoded.cgImage, properties as CFDictionary)
        guard CGImageDestinationFinalize(destination) else {
            throw TestError.cannotEncodeImage
        }
        return data as Data
    }

    private func imageProperties(at url: URL) throws -> [CFString: Any] {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any] else {
            throw TestError.cannotEncodeImage
        }
        return properties
    }

    private func makeDecodedImage(width: Int, height: Int) throws -> DecodedImage {
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        guard let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ), let image = context.makeImage() else {
            throw TestError.cannotCreateContext
        }

        return DecodedImage(cgImage: image, pixelSize: CGSize(width: width, height: height), isAnimated: false)
    }

    private enum TestError: Error {
        case cannotCreateContext
        case cannotEncodeImage
        case scanFailed
    }

    private func waitUntil(
        timeoutNanoseconds: UInt64 = 1_000_000_000,
        condition: @escaping @MainActor () -> Bool
    ) async {
        let deadline = DispatchTime.now().uptimeNanoseconds + timeoutNanoseconds
        while !condition() {
            if DispatchTime.now().uptimeNanoseconds >= deadline {
                XCTFail("Timed out waiting for condition")
                return
            }
            await Task.yield()
        }
    }
}

private actor ControlledScanner {
    typealias Handler = @Sendable (URL) throws -> [ImageItem]

    private struct PausedRequest {
        let handler: Handler
        var continuation: CheckedContinuation<[ImageItem], Error>?
        var isWaiting = false
    }

    private let handler: Handler
    private var pausedRequests: [URL: PausedRequest] = [:]

    init(handler: @escaping Handler) {
        self.handler = handler
    }

    func pause(url: URL) {
        pausedRequests[url] = PausedRequest(handler: handler)
    }

    func scan(containing url: URL) async throws -> [ImageItem] {
        if pausedRequests[url] != nil {
            return try await withCheckedThrowingContinuation { continuation in
                pausedRequests[url]?.continuation = continuation
                pausedRequests[url]?.isWaiting = true
            }
        }

        return try handler(url)
    }

    func waitUntilPaused(url: URL) async {
        while pausedRequests[url]?.isWaiting != true {
            await Task.yield()
        }
    }

    func resume(url: URL) throws {
        guard let request = pausedRequests.removeValue(forKey: url),
              let continuation = request.continuation else {
            return
        }
        continuation.resume(returning: try request.handler(url))
    }
}

private struct StubDecoder {
    let handler: @Sendable (URL, SupportedImageFormat) throws -> DecodedImage

    func decode(url: URL, format: SupportedImageFormat) throws -> DecodedImage {
        try handler(url, format)
    }
}

private final class FileVersionSequence: @unchecked Sendable {
    static let initial = CurrentFileVersion(
        device: 1,
        inode: 1,
        fileSize: 1,
        modificationNanoseconds: 1,
        changeNanoseconds: 1
    )
    static let replacement = CurrentFileVersion(
        device: 1,
        inode: 1,
        fileSize: 2,
        modificationNanoseconds: 2,
        changeNanoseconds: 2
    )

    private var values: [URL: [CurrentFileVersion?]]
    private var readCounts: [URL: Int] = [:]

    init(values: [URL: [CurrentFileVersion?]]) {
        self.values = values
    }

    func value(for url: URL) -> CurrentFileVersion? {
        let index = readCounts[url, default: 0]
        readCounts[url] = index + 1
        let sequence = values[url] ?? []
        return sequence.indices.contains(index) ? sequence[index] : sequence.last ?? nil
    }

    func hasReadReplacement(for url: URL) -> Bool {
        readCounts[url, default: 0] >= 2
    }
}

private final class DecodeSequence: @unchecked Sendable {
    private var images: [DecodedImage]

    init(images: [DecodedImage]) {
        self.images = images
    }

    func decode(url _: URL, format _: SupportedImageFormat) throws -> DecodedImage {
        guard !images.isEmpty else { throw ImageDecodeError.cannotCreateSource }
        return images.removeFirst()
    }
}

private actor ControlledImageLoader {
    private struct PausedRequest {
        var continuation: CheckedContinuation<DecodedImage, Error>?
        var isWaiting = false
    }

    private let images: [URL: DecodedImage]
    private var pausedURLs: Set<URL> = []
    private var pausedRequests: [URL: PausedRequest] = [:]

    init(images: [URL: DecodedImage]) {
        self.images = images
    }

    func pauseNextLoad(for url: URL) {
        pausedURLs.insert(url)
    }

    func load(url: URL, format _: SupportedImageFormat) async throws -> DecodedImage {
        if pausedURLs.remove(url) != nil {
            return try await withCheckedThrowingContinuation { continuation in
                pausedRequests[url] = PausedRequest(continuation: continuation, isWaiting: true)
            }
        }

        guard let image = images[url] else {
            throw ImageDecodeError.cannotCreateSource
        }
        return image
    }

    func waitUntilPaused(url: URL) async {
        while pausedRequests[url]?.isWaiting != true {
            await Task.yield()
        }
    }

    func resume(url: URL) throws {
        guard let request = pausedRequests.removeValue(forKey: url),
              let continuation = request.continuation,
              let image = images[url] else {
            return
        }

        continuation.resume(returning: image)
    }
}

private actor SequencedImageLoader {
    struct Plan: Sendable {
        let image: DecodedImage
        let pauseID: String?

        init(image: DecodedImage, pauseID: String? = nil) {
            self.image = image
            self.pauseID = pauseID
        }
    }

    private struct PausedRequest {
        let image: DecodedImage
        var continuation: CheckedContinuation<DecodedImage, Error>?
    }

    private var plans: [URL: [Plan]]
    private var pausedRequests: [String: PausedRequest] = [:]
    private var completedIDs: Set<String> = []

    init(plans: [URL: [Plan]]) {
        self.plans = plans
    }

    func load(url: URL, format _: SupportedImageFormat) async throws -> DecodedImage {
        guard var urlPlans = plans[url], !urlPlans.isEmpty else {
            throw ImageDecodeError.cannotCreateSource
        }
        let plan = urlPlans.removeFirst()
        plans[url] = urlPlans
        guard let pauseID = plan.pauseID else { return plan.image }

        let image = try await withCheckedThrowingContinuation { continuation in
            pausedRequests[pauseID] = PausedRequest(image: plan.image, continuation: continuation)
        }
        completedIDs.insert(pauseID)
        return image
    }

    func waitUntilPaused(id: String) async {
        while pausedRequests[id]?.continuation == nil {
            await Task.yield()
        }
    }

    func resume(id: String) throws {
        guard let request = pausedRequests.removeValue(forKey: id),
              let continuation = request.continuation else {
            return
        }
        continuation.resume(returning: request.image)
    }

    func waitUntilCompleted(id: String) async {
        while !completedIDs.contains(id) {
            await Task.yield()
        }
    }
}
