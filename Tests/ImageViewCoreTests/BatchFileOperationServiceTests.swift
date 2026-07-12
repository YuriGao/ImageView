import Foundation
import XCTest
@testable import ImageViewCore

final class BatchFileOperationServiceTests: XCTestCase {
    func testRenamePlanPreservesExtensionsAndRejectsExistingUnselectedConflict() throws {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let first = try writeFile(named: "old-a.jpg", in: root)
        let second = try writeFile(named: "old-b.png", in: root)
        _ = try writeFile(named: "Photo 02.png", in: root)

        let plan = BatchFileOperationService().planBatchRename(
            urls: [first, second],
            baseName: "Photo",
            startNumber: 1,
            padding: 2
        )

        XCTAssertEqual(plan.proposals.map(\.destination.lastPathComponent), ["Photo 01.jpg", "Photo 02.png"])
        XCTAssertFalse(plan.isExecutable)
        XCTAssertEqual(plan.failures.count, 1)
        XCTAssertEqual(plan.failures.first?.url, second)
        XCTAssertEqual(plan.failures.first?.reason, .destinationExists)
    }

    func testMoveToFolderSkipConflictDoesNotOverwriteDestinationFile() throws {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let sourceFolder = root.appendingPathComponent("source", isDirectory: true)
        let destinationFolder = root.appendingPathComponent("destination", isDirectory: true)
        try FileManager.default.createDirectory(at: sourceFolder, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: destinationFolder, withIntermediateDirectories: true)
        let source = try writeFile(named: "same.jpg", contents: "source", in: sourceFolder)
        let destination = try writeFile(named: "same.jpg", contents: "destination", in: destinationFolder)

        let result = BatchFileOperationService().moveToFolder(
            [source],
            destinationFolder: destinationFolder,
            conflictPolicy: .skip
        )

        XCTAssertEqual(result.succeeded.count, 0)
        XCTAssertEqual(result.failures.count, 1)
        XCTAssertEqual(result.failures.first?.reason, .destinationExists)
        XCTAssertTrue(FileManager.default.fileExists(atPath: source.path))
        XCTAssertEqual(try String(contentsOf: destination, encoding: .utf8), "destination")
    }

    func testExecuteRenamePlanHandlesIntraSelectionSwap() throws {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let first = try writeFile(named: "a.jpg", contents: "first", in: root)
        let second = try writeFile(named: "b.jpg", contents: "second", in: root)
        let plan = BatchRenamePlan(
            proposals: [
                RenameProposal(source: first, destination: second),
                RenameProposal(source: second, destination: first)
            ],
            failures: []
        )

        let result = BatchFileOperationService().executeRenamePlan(plan)

        XCTAssertTrue(result.failures.isEmpty)
        XCTAssertEqual(Set(result.succeeded), Set([first, second]))
        XCTAssertEqual(try String(contentsOf: first, encoding: .utf8), "second")
        XCTAssertEqual(try String(contentsOf: second, encoding: .utf8), "first")
    }

    private func makeTemporaryDirectory() throws -> URL {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }

    @discardableResult
    private func writeFile(named name: String, contents: String = "x", in folder: URL) throws -> URL {
        let url = folder.appendingPathComponent(name)
        try Data(contents.utf8).write(to: url)
        return url
    }
}
