import AppKit
import ImageViewCore
import XCTest
@testable import ImageViewApp

@MainActor
final class ThumbnailProviderTests: XCTestCase {
    func testCancellationPreventsCompletion() {
        let provider = ThumbnailProvider(loader: { _, _, completion in
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                completion(.success(NSImage(size: NSSize(width: 12, height: 12))))
            }
            return {}
        })
        let item = ImageItem(url: URL(fileURLWithPath: "/tmp/cancel-me.png"), format: .png)
        let completionNotCalled = expectation(description: "completion not called after cancellation")
        completionNotCalled.isInverted = true

        let request = provider.loadThumbnail(for: item) { _ in
            completionNotCalled.fulfill()
        }
        request.cancel()

        wait(for: [completionNotCalled], timeout: 0.15)
    }
}
