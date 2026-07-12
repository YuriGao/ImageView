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

    func testRenamePlanRejectsColonInBaseName() throws {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let source = try writeFile(named: "old-a.jpg", in: root)

        let plan = BatchFileOperationService().planBatchRename(
            urls: [source],
            baseName: "bad:name",
            startNumber: 1,
            padding: 2
        )

        XCTAssertFalse(plan.isExecutable)
        XCTAssertEqual(plan.failures, [
            BatchFileFailure(url: source, reason: .invalidName)
        ])
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

    func testPlanMoveToFolderReturnsEveryConflictWithoutMovingSources() throws {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let sourceFolder = root.appendingPathComponent("source", isDirectory: true)
        let destinationFolder = root.appendingPathComponent("destination", isDirectory: true)
        try FileManager.default.createDirectory(at: sourceFolder, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: destinationFolder, withIntermediateDirectories: true)
        let first = try writeFile(named: "first.jpg", in: sourceFolder)
        let second = try writeFile(named: "second.jpg", in: sourceFolder)
        let available = try writeFile(named: "available.jpg", in: sourceFolder)
        _ = try writeFile(named: "first.jpg", in: destinationFolder)
        _ = try writeFile(named: "second.jpg", in: destinationFolder)

        let plan = BatchFileOperationService().planMoveToFolder(
            [first, second, available],
            destinationFolder: destinationFolder,
            conflictPolicy: .skip
        )

        XCTAssertEqual(plan.proposals, [
            BatchMoveProposal(
                source: available,
                destination: destinationFolder.appendingPathComponent("available.jpg")
            )
        ])
        XCTAssertEqual(plan.conflictingNames, ["first.jpg", "second.jpg"])
        XCTAssertTrue(FileManager.default.fileExists(atPath: first.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: second.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: available.path))
    }

    func testPlanMoveKeepBothReservesNamesAcrossBatch() throws {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let sourceFolder = root.appendingPathComponent("source", isDirectory: true)
        let nestedFolder = sourceFolder.appendingPathComponent("nested", isDirectory: true)
        let destinationFolder = root.appendingPathComponent("destination", isDirectory: true)
        try FileManager.default.createDirectory(at: nestedFolder, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: destinationFolder, withIntermediateDirectories: true)
        let sourceA = try writeFile(named: "photo.png", in: sourceFolder)
        let sourceB = try writeFile(named: "photo.png", in: nestedFolder)
        _ = try writeFile(named: "photo.png", in: destinationFolder)
        _ = try writeFile(named: "photo copy.png", in: destinationFolder)

        let plan = BatchFileOperationService().planMoveToFolder(
            [sourceA, sourceB],
            destinationFolder: destinationFolder,
            conflictPolicy: .keepBoth
        )

        XCTAssertEqual(plan.proposals.map(\.destination.lastPathComponent), [
            "photo copy 2.png", "photo copy 3.png"
        ])
        XCTAssertTrue(plan.failures.isEmpty)
    }

    func testExecuteMovePlanDoesNotOverwriteConflictCreatedAfterPlanning() throws {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let sourceFolder = root.appendingPathComponent("source", isDirectory: true)
        let destinationFolder = root.appendingPathComponent("destination", isDirectory: true)
        try FileManager.default.createDirectory(at: sourceFolder, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: destinationFolder, withIntermediateDirectories: true)
        let source = try writeFile(named: "same.jpg", contents: "source", in: sourceFolder)
        let service = BatchFileOperationService()
        let plan = service.planMoveToFolder(
            [source],
            destinationFolder: destinationFolder,
            conflictPolicy: .skip
        )
        let destination = try writeFile(named: "same.jpg", contents: "destination", in: destinationFolder)

        let result = service.executeMovePlan(plan)

        XCTAssertTrue(result.succeeded.isEmpty)
        XCTAssertEqual(result.failures, [
            BatchFileFailure(url: source, reason: .destinationExists)
        ])
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

    func testExecuteRenamePlanRestoresEveryOriginalWhenPhaseOneMoveFails() throws {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let first = try writeFile(named: "a.jpg", contents: "first", in: root)
        let second = try writeFile(named: "b.jpg", contents: "second", in: root)
        let firstDestination = root.appendingPathComponent("renamed-a.jpg")
        let secondDestination = root.appendingPathComponent("renamed-b.jpg")
        let fileSystem = FaultInjectingBatchFileSystem(failingMoveCalls: [2])
        let service = BatchFileOperationService(fileSystem: fileSystem)

        let result = service.executeRenamePlan(BatchRenamePlan(
            proposals: [
                RenameProposal(source: first, destination: firstDestination),
                RenameProposal(source: second, destination: secondDestination)
            ],
            failures: []
        ))

        XCTAssertTrue(result.succeeded.isEmpty)
        XCTAssertEqual(result.failures.map(\.url), [second])
        XCTAssertTrue(result.recoveryFailures.isEmpty)
        XCTAssertEqual(try String(contentsOf: first, encoding: .utf8), "first")
        XCTAssertEqual(try String(contentsOf: second, encoding: .utf8), "second")
        XCTAssertFalse(FileManager.default.fileExists(atPath: firstDestination.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: secondDestination.path))
        try assertNoRenameTemporaryFiles(in: root)
    }

    func testExecuteRenamePlanReversesCommittedDestinationsBeforeRestoringOriginalsOnPhaseTwoFailure() throws {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let first = try writeFile(named: "a.jpg", contents: "first", in: root)
        let second = try writeFile(named: "b.jpg", contents: "second", in: root)
        let firstDestination = root.appendingPathComponent("renamed-a.jpg")
        let secondDestination = root.appendingPathComponent("renamed-b.jpg")
        let fileSystem = FaultInjectingBatchFileSystem(failingMoveCalls: [4])
        let service = BatchFileOperationService(fileSystem: fileSystem)

        let result = service.executeRenamePlan(BatchRenamePlan(
            proposals: [
                RenameProposal(source: first, destination: firstDestination),
                RenameProposal(source: second, destination: secondDestination)
            ],
            failures: []
        ))

        XCTAssertTrue(result.succeeded.isEmpty)
        XCTAssertEqual(result.failures.map(\.url), [second])
        XCTAssertTrue(result.recoveryFailures.isEmpty)
        XCTAssertEqual(try String(contentsOf: first, encoding: .utf8), "first")
        XCTAssertEqual(try String(contentsOf: second, encoding: .utf8), "second")
        XCTAssertFalse(FileManager.default.fileExists(atPath: firstDestination.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: secondDestination.path))
        try assertNoRenameTemporaryFiles(in: root)

        let successfulMoves = fileSystem.moveAttempts.filter { !$0.didFail }
        let destinationRollbackIndex = try XCTUnwrap(successfulMoves.firstIndex {
            $0.source == firstDestination && $0.destination.lastPathComponent.hasPrefix(".batch-rename-")
        })
        let firstOriginalRestoreIndex = try XCTUnwrap(successfulMoves.firstIndex { $0.destination == first })
        let secondOriginalRestoreIndex = try XCTUnwrap(successfulMoves.firstIndex { $0.destination == second })
        XCTAssertLessThan(destinationRollbackIndex, firstOriginalRestoreIndex)
        XCTAssertLessThan(destinationRollbackIndex, secondOriginalRestoreIndex)
    }

    func testExecuteRenamePlanReportsBestKnownActualURLWhenRollbackFails() throws {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let first = try writeFile(named: "a.jpg", contents: "first", in: root)
        let second = try writeFile(named: "b.jpg", contents: "second", in: root)
        let firstDestination = root.appendingPathComponent("renamed-a.jpg")
        let secondDestination = root.appendingPathComponent("renamed-b.jpg")
        let fileSystem = FaultInjectingBatchFileSystem(failingMoveCalls: [4, 7])
        let service = BatchFileOperationService(fileSystem: fileSystem)

        let result = service.executeRenamePlan(BatchRenamePlan(
            proposals: [
                RenameProposal(source: first, destination: firstDestination),
                RenameProposal(source: second, destination: secondDestination)
            ],
            failures: []
        ))

        XCTAssertTrue(result.succeeded.isEmpty)
        XCTAssertEqual(result.failures.map(\.url), [second])
        XCTAssertEqual(result.recoveryFailures.count, 1)
        let recoveryFailure = try XCTUnwrap(result.recoveryFailures.first)
        XCTAssertEqual(recoveryFailure.expectedURL, first)
        XCTAssertTrue(recoveryFailure.actualURL.lastPathComponent.hasPrefix(".batch-rename-"))
        XCTAssertTrue(FileManager.default.fileExists(atPath: recoveryFailure.actualURL.path))
        XCTAssertEqual(try String(contentsOf: recoveryFailure.actualURL, encoding: .utf8), "first")
        XCTAssertEqual(try String(contentsOf: second, encoding: .utf8), "second")
        XCTAssertFalse(FileManager.default.fileExists(atPath: firstDestination.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: secondDestination.path))
    }

    func testExecuteRenamePlanReportsDestinationAsActualURLWhenCommittedMoveCannotReverse() throws {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let first = try writeFile(named: "a.jpg", contents: "first", in: root)
        let second = try writeFile(named: "b.jpg", contents: "second", in: root)
        let firstDestination = root.appendingPathComponent("renamed-a.jpg")
        let secondDestination = root.appendingPathComponent("renamed-b.jpg")
        let fileSystem = FaultInjectingBatchFileSystem(failingMoveCalls: [4, 5])
        let service = BatchFileOperationService(fileSystem: fileSystem)

        let result = service.executeRenamePlan(BatchRenamePlan(
            proposals: [
                RenameProposal(source: first, destination: firstDestination),
                RenameProposal(source: second, destination: secondDestination)
            ],
            failures: []
        ))

        XCTAssertEqual(result.recoveryFailures, [
            BatchRecoveryFailure(
                expectedURL: first,
                actualURL: firstDestination,
                reason: "Injected move failure at call 5"
            )
        ])
        XCTAssertEqual(try String(contentsOf: firstDestination, encoding: .utf8), "first")
        XCTAssertEqual(try String(contentsOf: second, encoding: .utf8), "second")
        XCTAssertFalse(FileManager.default.fileExists(atPath: first.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: secondDestination.path))
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

    private func assertNoRenameTemporaryFiles(in folder: URL) throws {
        let names = try FileManager.default.contentsOfDirectory(atPath: folder.path)
        XCTAssertFalse(names.contains { $0.hasPrefix(".batch-rename-") && $0.hasSuffix(".tmp") })
    }
}

private final class FaultInjectingBatchFileSystem: BatchFileSystem, @unchecked Sendable {
    struct MoveAttempt: Equatable {
        let source: URL
        let destination: URL
        let didFail: Bool
    }

    private let fileManager = FileManager.default
    private let failingMoveCalls: Set<Int>
    private(set) var moveAttempts: [MoveAttempt] = []

    init(failingMoveCalls: Set<Int>) {
        self.failingMoveCalls = failingMoveCalls
    }

    func fileExists(at url: URL) -> Bool {
        fileManager.fileExists(atPath: url.path)
    }

    func directoryContents(at url: URL) throws -> [URL] {
        try fileManager.contentsOfDirectory(at: url, includingPropertiesForKeys: nil)
    }

    func moveItem(at source: URL, to destination: URL) throws {
        let call = moveAttempts.count + 1
        let shouldFail = failingMoveCalls.contains(call)
        moveAttempts.append(MoveAttempt(source: source, destination: destination, didFail: shouldFail))
        if shouldFail {
            throw FaultInjectionError.move(call)
        }
        try fileManager.moveItem(at: source, to: destination)
    }

    func trashItem(at url: URL) throws {
        var resultingURL: NSURL?
        try fileManager.trashItem(at: url, resultingItemURL: &resultingURL)
    }
}

private enum FaultInjectionError: LocalizedError {
    case move(Int)

    var errorDescription: String? {
        switch self {
        case .move(let call): "Injected move failure at call \(call)"
        }
    }
}
