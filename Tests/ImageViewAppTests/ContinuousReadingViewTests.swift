import AppKit
import XCTest
@testable import ImageViewApp
@testable import ImageViewCore

@MainActor
final class ContinuousReadingViewTests: XCTestCase {
    func testContinuousReadingKeepsAtMostCurrentPlusTwoNeighborsPerSide() {
        let view = ContinuousReadingView(frame: CGRect(x: 0, y: 0, width: 800, height: 600))
        let items = (0..<12).map { index in
            ImageItem(
                url: URL(fileURLWithPath: "/tmp/\(index).png"),
                format: .png
            )
        }
        let pages = items.enumerated().map { index, item in
            ContinuousReadingPage(
                item: item,
                image: (3...7).contains(index) ? makeDecodedImage(width: 400, height: 600) : nil
            )
        }

        view.apply(pages: pages, currentItemID: items[5].id)

        XCTAssertEqual(ContinuousReadingView.preloadRadius, 2)
        XCTAssertEqual(ContinuousReadingView.maximumDecodedPageCount, 5)
        XCTAssertEqual(view.testingPageCount, 12, "the full directory remains vertically reachable")
        XCTAssertEqual(view.testingDecodedPageCount, 5)
        XCTAssertEqual(view.testingPageURLs, items.map(\.url))
    }

    func testScrollingToUnloadedDirectoryPageRequestsANewDecodeWindow() {
        let view = ContinuousReadingView(frame: CGRect(x: 0, y: 0, width: 800, height: 600))
        let items = (0..<12).map {
            ImageItem(url: URL(fileURLWithPath: "/tmp/\($0).png"), format: .png)
        }
        var focusedID: ImageItem.ID?
        view.onFocusedItemChanged = { focusedID = $0 }
        view.apply(
            pages: items.map { ContinuousReadingPage(item: $0, image: nil) },
            currentItemID: items[2].id
        )

        view.testingScrollToItem(with: items[8].id)

        XCTAssertEqual(focusedID, items[8].id)
    }

    func testMissingNeighborDecodeRendersAsPlaceholderWithoutChangingOrder() {
        let view = ContinuousReadingView(frame: CGRect(x: 0, y: 0, width: 800, height: 600))
        let first = ImageItem(url: URL(fileURLWithPath: "/tmp/a.png"), format: .png)
        let second = ImageItem(url: URL(fileURLWithPath: "/tmp/b.png"), format: .png)

        view.apply(
            pages: [
                ContinuousReadingPage(item: first, image: makeDecodedImage(width: 400, height: 300)),
                ContinuousReadingPage(item: second, image: nil)
            ],
            currentItemID: first.id
        )

        XCTAssertEqual(view.testingPageURLs, [first.url, second.url])
        XCTAssertEqual(view.testingDecodedPageCount, 1)
    }

    private func makeDecodedImage(width: Int, height: Int) -> DecodedImage {
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )!
        let image = context.makeImage()!
        return DecodedImage(
            cgImage: image,
            pixelSize: CGSize(width: width, height: height),
            isAnimated: false
        )
    }
}
