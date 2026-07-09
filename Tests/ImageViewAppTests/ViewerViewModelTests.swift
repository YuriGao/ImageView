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

        XCTAssertEqual(viewModel.errorMessage, "无法打开图片：broken.png")
        XCTAssertNil(viewModel.currentImage)
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

        XCTAssertEqual(viewModel.errorMessage, "无法打开图片：broken.png")
        XCTAssertNil(viewModel.currentImage)
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

    func testHUDMetadataTracksNavigationAndSelection() async throws {
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

        XCTAssertEqual(viewModel.positionText, "0 / 0")

        await viewModel.open(url: firstURL)
        XCTAssertEqual(viewModel.currentFilename, "first.png")
        XCTAssertEqual(viewModel.positionText, "1 / 2")

        viewModel.showNext()
        await waitUntil { viewModel.positionText == "2 / 2" }
        XCTAssertEqual(viewModel.currentFilename, "second.png")

        let selected = try XCTUnwrap(viewModel.navigationState?.items.first)
        viewModel.show(item: selected)
        await waitUntil { viewModel.positionText == "1 / 2" }
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
        XCTAssertFalse(ViewerViewModel.canPreloadInBackground(.svg))
        XCTAssertFalse(ViewerViewModel.canPreloadInBackground(.webp))
        XCTAssertFalse(ViewerViewModel.canPreloadInBackground(.avif))
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

    func testDiscardCurrentEditsClearsUnsavedStateWithoutReloading() async throws {
        let imageURL = try makeTemporaryPNG(width: 6, height: 4, name: "discard-in-place")
        defer { try? FileManager.default.removeItem(at: imageURL.deletingLastPathComponent()) }

        let viewModel = ViewerViewModel()
        await viewModel.open(url: imageURL)
        let editedSizeBeforeDiscard = CGSize(width: 4, height: 6)

        viewModel.applyEdit(.rotateClockwise)
        XCTAssertEqual(viewModel.currentImage?.pixelSize, editedSizeBeforeDiscard)

        viewModel.discardCurrentEdits()

        XCTAssertFalse(viewModel.hasUnsavedEdits)
        XCTAssertEqual(viewModel.currentImage?.pixelSize, editedSizeBeforeDiscard)
        XCTAssertNil(viewModel.errorMessage)
    }

    private func makePNGData(width: Int, height: Int) throws -> Data {
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

        context.setFillColor(red: 0.2, green: 0.4, blue: 0.8, alpha: 1)
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

    private func makeTemporaryPNG(width: Int, height: Int, name: String) throws -> URL {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let imageURL = root.appendingPathComponent("\(name).png")
        try makePNGData(width: width, height: height).write(to: imageURL)
        return imageURL
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
