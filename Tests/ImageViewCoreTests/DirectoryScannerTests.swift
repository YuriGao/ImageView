import Foundation
import XCTest
@testable import ImageViewCore

final class DirectoryScannerTests: XCTestCase {
    func testScansOnlySupportedImagesInOpenedFilesDirectory() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let opened = root.appendingPathComponent("image-2.png")
        let first = root.appendingPathComponent("image-1.jpg")
        let ignored = root.appendingPathComponent("notes.txt")
        FileManager.default.createFile(atPath: opened.path, contents: Data())
        FileManager.default.createFile(atPath: first.path, contents: Data())
        FileManager.default.createFile(atPath: ignored.path, contents: Data())

        let items = try await DirectoryScanner().scan(containing: opened)

        XCTAssertEqual(items.map(\.url.lastPathComponent), ["image-1.jpg", "image-2.png"])
        XCTAssertTrue(items.contains { $0.url == opened })
    }
}
