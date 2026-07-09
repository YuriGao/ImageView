import CoreGraphics
import Foundation
import ImageIO
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

    private enum TestError: Error {
        case cannotCreateContext
        case cannotEncodeImage
    }
}
