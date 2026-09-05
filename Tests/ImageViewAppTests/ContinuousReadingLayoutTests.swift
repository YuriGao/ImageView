import AppKit
import XCTest
@testable import ImageViewApp
@testable import ImageViewCore

final class ContinuousReadingLayoutTests: XCTestCase {
    func testEvictingBitmapsPreservesPageHeightsAndFollowingPositions() throws {
        let items = makeItems(count: 3)
        let context = CGContext(data: nil, width: 10, height: 40, bitsPerComponent: 8, bytesPerRow: 40, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        let image = DecodedImage(cgImage: context.makeImage()!, pixelSize: CGSize(width: 10, height: 40), isAnimated: false)
        var layout = ContinuousReadingLayout()
        layout.update(items.map { ContinuousReadingPage(item: $0, image: image) })
        layout.prepare(width: 800)
        let original = items.map { layout.frame(for: $0.id) }
        layout.update(items.map { ContinuousReadingPage(item: $0, image: nil) })
        layout.prepare(width: 800)
        XCTAssertEqual(items.map { layout.frame(for: $0.id) }, original)
        XCTAssertEqual(layout.buildCount, 1)
    }

    func testTenThousandPagesReuseGeometryAndFindVisibleRangeWithoutScanningAllPages() throws {
        let items = makeItems(count: 10_000)
        var layout = ContinuousReadingLayout()
        layout.update(items.map { ContinuousReadingPage(item: $0, image: nil) })
        layout.prepare(width: 800)
        let frame = try XCTUnwrap(layout.frame(for: items[8000].id))
        for _ in 0..<1000 {
            layout.prepare(width: 800)
            XCTAssertEqual(layout.nearestItemID(to: frame.midY), items[8000].id)
            XCTAssertEqual(layout.index(at: CGPoint(x: frame.midX, y: frame.midY)), 8000)
            XCTAssertEqual(layout.visibleRange(in: frame), 8000..<8001)
        }
        XCTAssertEqual(layout.buildCount, 1)
        XCTAssertNil(layout.index(at: CGPoint(x: frame.midX, y: frame.maxY + 5)))
        layout.prepare(width: 600)
        XCTAssertEqual(layout.buildCount, 2)
        layout.update([])
        layout.prepare(width: 600)
        XCTAssertNil(layout.nearestItemID(to: 0))
        XCTAssertEqual(layout.requiredHeight, 0)
    }

    private func makeItems(count: Int) -> [ImageItem] {
        (0..<count).map { ImageItem(url: URL(fileURLWithPath: "/tmp/reading-\($0).png"), format: .png) }
    }
}
