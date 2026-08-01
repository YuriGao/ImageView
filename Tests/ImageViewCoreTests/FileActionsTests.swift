import XCTest
@testable import ImageViewCore

final class FileActionsTests: XCTestCase {
    func testRestoreFromTrashMovesItemBackToOriginalLocation() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let trashedURL = root.appendingPathComponent("trashed.png")
        let originalURL = root.appendingPathComponent("original.png")
        try Data("image".utf8).write(to: trashedURL)

        try FileActions().restoreFromTrash(trashedURL, to: originalURL)

        XCTAssertTrue(FileManager.default.fileExists(atPath: originalURL.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: trashedURL.path))
    }

    func testRestoreFromTrashDoesNotOverwriteExistingOriginal() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let trashedURL = root.appendingPathComponent("trashed.png")
        let originalURL = root.appendingPathComponent("original.png")
        try Data("trashed".utf8).write(to: trashedURL)
        try Data("existing".utf8).write(to: originalURL)

        XCTAssertThrowsError(try FileActions().restoreFromTrash(trashedURL, to: originalURL)) { error in
            XCTAssertEqual(error as? FileActionError, .restoreDestinationExists)
        }
        XCTAssertEqual(try Data(contentsOf: originalURL), Data("existing".utf8))
        XCTAssertTrue(FileManager.default.fileExists(atPath: trashedURL.path))
    }

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

    func testRenameRejectsEmptyName() {
        XCTAssertEqual(renameError(for: "   "), .emptyName)
    }

    func testRenameRejectsPathLikeNames() {
        XCTAssertEqual(renameError(for: "nested/name"), .invalidBaseName)
        XCTAssertEqual(renameError(for: "."), .invalidBaseName)
        XCTAssertEqual(renameError(for: ".."), .invalidBaseName)
    }

    private func renameError(for newBaseName: String) -> FileActionError? {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try? FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let original = root.appendingPathComponent("old.png")
        FileManager.default.createFile(atPath: original.path, contents: Data("x".utf8))

        do {
            _ = try FileActions().rename(original, to: newBaseName)
            return nil
        } catch let error as FileActionError {
            return error
        } catch {
            XCTFail("Unexpected error: \(error)")
            return nil
        }
    }
}
