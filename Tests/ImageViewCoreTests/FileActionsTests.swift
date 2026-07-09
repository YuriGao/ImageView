import XCTest
@testable import ImageViewCore

final class FileActionsTests: XCTestCase {
    func testRenamePreservesExtension() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let original = root.appendingPathComponent("old.png")
        FileManager.default.createFile(atPath: original.path, contents: Data("x".utf8))

        let renamed = try FileActions().rename(original, to: "new")

        XCTAssertEqual(renamed.lastPathComponent, "new.png")
        XCTAssertTrue(FileManager.default.fileExists(atPath: renamed.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: original.path))
    }

    func testAbsolutePathReturnsPathString() {
        let url = URL(fileURLWithPath: "/tmp/a.png")
        XCTAssertEqual(FileActions().absolutePath(for: url), "/tmp/a.png")
    }
}
