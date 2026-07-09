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

    func testOpenKeepsLatestRequestWhenEarlierScanFinishesLater() async throws {
        let firstURL = URL(fileURLWithPath: "/tmp/first.png")
        let secondURL = URL(fileURLWithPath: "/tmp/second.png")
        let firstImage = try makeDecodedImage(width: 3, height: 2)
        let secondImage = try makeDecodedImage(width: 9, height: 7)
        let scanner = ControlledScanner { url in
            let format = try XCTUnwrap(SupportedImageFormat(fileExtension: url.pathExtension))
            return [ImageItem(url: url, format: format)]
        }
        let decoder = StubDecoder { url, _ in
            switch url {
            case firstURL:
                return firstImage
            case secondURL:
                return secondImage
            default:
                throw ImageDecodeError.cannotCreateSource
            }
        }
        let viewModel = ViewerViewModel(
            scanContainingDirectory: scanner.scan(containing:),
            decodeImageAtURL: decoder.decode(url:format:)
        )

        await scanner.pause(url: firstURL)
        let firstOpen = Task { await viewModel.open(url: firstURL) }
        await scanner.waitUntilPaused(url: firstURL)

        await viewModel.open(url: secondURL)
        try await scanner.resume(url: firstURL)
        _ = await firstOpen.value

        XCTAssertEqual(viewModel.currentImage?.pixelSize, CGSize(width: 9, height: 7))
        XCTAssertEqual(viewModel.navigationState?.currentItem?.url, secondURL)
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
