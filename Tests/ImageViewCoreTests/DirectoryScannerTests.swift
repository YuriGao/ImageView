import Foundation
import XCTest
@testable import ImageViewCore

final class DirectoryScannerTests: XCTestCase {
    private final class RecordingFileManager: FileManager {
        private(set) var enumeratedOnMainThread = false

        override func contentsOfDirectory(
            at url: URL,
            includingPropertiesForKeys keys: [URLResourceKey]?,
            options mask: FileManager.DirectoryEnumerationOptions = []
        ) throws -> [URL] {
            enumeratedOnMainThread = Thread.isMainThread
            return try super.contentsOfDirectory(at: url, includingPropertiesForKeys: keys, options: mask)
        }
    }

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

    func testScansExplicitFolderUsingNaturalSortAndSupportedFormats() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        FileManager.default.createFile(atPath: root.appendingPathComponent("image-10.jpg").path, contents: Data())
        FileManager.default.createFile(atPath: root.appendingPathComponent("notes.txt").path, contents: Data())
        FileManager.default.createFile(atPath: root.appendingPathComponent("image-2.png").path, contents: Data())

        let items = try await DirectoryScanner().scan(folder: root)

        XCTAssertEqual(items.map(\.url.lastPathComponent), ["image-2.png", "image-10.jpg"])
    }

    @MainActor
    func testDirectoryEnumerationRunsOffTheMainThread() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let opened = root.appendingPathComponent("image-1.png")
        FileManager.default.createFile(atPath: opened.path, contents: Data())

        let fileManager = RecordingFileManager()
        let scanner = DirectoryScanner(fileManager: fileManager)

        _ = try await scanner.scan(containing: opened)

        XCTAssertFalse(fileManager.enumeratedOnMainThread)
    }
}
