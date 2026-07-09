import XCTest
@testable import ImageViewCore

final class PerformanceGuardTests: XCTestCase {
    func testDirectoryScanDoesNotRequireImageDecoding() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        for index in 0..<1000 {
            FileManager.default.createFile(atPath: root.appendingPathComponent("image-\(index).png").path, contents: Data())
        }

        let opened = root.appendingPathComponent("image-500.png")
        let items = try await DirectoryScanner().scan(containing: opened)
        XCTAssertEqual(items.count, 1000)
    }
}
