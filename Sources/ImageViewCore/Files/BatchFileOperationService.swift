import Foundation

public protocol BatchFileSystem: Sendable {
    func fileExists(at url: URL) -> Bool
    func directoryContents(at url: URL) throws -> [URL]
    func moveItem(at source: URL, to destination: URL) throws
    func trashItem(at url: URL) throws
}

public struct DefaultBatchFileSystem: BatchFileSystem {
    public init() {}

    public func fileExists(at url: URL) -> Bool {
        FileManager.default.fileExists(atPath: url.path)
    }

    public func directoryContents(at url: URL) throws -> [URL] {
        try FileManager.default.contentsOfDirectory(at: url, includingPropertiesForKeys: nil)
    }

    public func moveItem(at source: URL, to destination: URL) throws {
        try FileManager.default.moveItem(at: source, to: destination)
    }

    public func trashItem(at url: URL) throws {
        var resultingURL: NSURL?
        try FileManager.default.trashItem(at: url, resultingItemURL: &resultingURL)
    }
}

public enum BatchFileFailureReason: Equatable {
    case emptyName
    case invalidName
    case sourceMissing
    case destinationExists
    case duplicateDestination
    case trashFailed(String)
    case moveFailed(String)
    case renameFailed(String)
}

public enum MoveConflictPolicy: Equatable {
    case skip
    case keepBoth
}

public struct BatchFileFailure: Equatable {
    public let url: URL
    public let reason: BatchFileFailureReason

    public init(url: URL, reason: BatchFileFailureReason) {
        self.url = url
        self.reason = reason
    }
}

public struct BatchMoveProposal: Equatable, Sendable {
    public let source: URL
    public let destination: URL

    public init(source: URL, destination: URL) {
        self.source = source
        self.destination = destination
    }
}

public struct BatchMovePlan: Equatable, @unchecked Sendable {
    public let proposals: [BatchMoveProposal]
    public let failures: [BatchFileFailure]

    public var conflictingNames: [String] {
        failures.compactMap { $0.reason == .destinationExists ? $0.url.lastPathComponent : nil }
    }

    public init(proposals: [BatchMoveProposal], failures: [BatchFileFailure]) {
        self.proposals = proposals
        self.failures = failures
    }
}

public struct BatchOperationResult: Equatable {
    public let succeeded: [URL]
    public let failures: [BatchFileFailure]
    public let recoveryFailures: [BatchRecoveryFailure]

    public init(
        succeeded: [URL] = [],
        failures: [BatchFileFailure] = [],
        recoveryFailures: [BatchRecoveryFailure] = []
    ) {
        self.succeeded = succeeded
        self.failures = failures
        self.recoveryFailures = recoveryFailures
    }
}

public struct BatchRecoveryFailure: Equatable, Sendable {
    public let expectedURL: URL
    public let actualURL: URL
    public let reason: String

    public init(expectedURL: URL, actualURL: URL, reason: String) {
        self.expectedURL = expectedURL
        self.actualURL = actualURL
        self.reason = reason
    }
}

public struct RenameProposal: Equatable {
    public let source: URL
    public let destination: URL

    public init(source: URL, destination: URL) {
        self.source = source
        self.destination = destination
    }
}

public struct BatchRenamePlan: Equatable {
    public let proposals: [RenameProposal]
    public let failures: [BatchFileFailure]

    public var isExecutable: Bool {
        failures.isEmpty
    }

    public init(proposals: [RenameProposal], failures: [BatchFileFailure]) {
        self.proposals = proposals
        self.failures = failures
    }
}

public final class BatchFileOperationService {
    private let fileSystem: any BatchFileSystem

    public init(fileSystem: any BatchFileSystem = DefaultBatchFileSystem()) {
        self.fileSystem = fileSystem
    }

    public func moveToTrash(_ urls: [URL]) -> BatchOperationResult {
        var succeeded: [URL] = []
        var failures: [BatchFileFailure] = []

        for url in urls {
            do {
                guard fileSystem.fileExists(at: url) else {
                    failures.append(BatchFileFailure(url: url, reason: .sourceMissing))
                    continue
                }
                try fileSystem.trashItem(at: url)
                succeeded.append(url)
            } catch {
                failures.append(BatchFileFailure(url: url, reason: .trashFailed(error.localizedDescription)))
            }
        }

        return BatchOperationResult(succeeded: succeeded, failures: failures)
    }

    public func moveToFolder(
        _ urls: [URL],
        destinationFolder: URL,
        conflictPolicy: MoveConflictPolicy
    ) -> BatchOperationResult {
        executeMovePlan(planMoveToFolder(
            urls,
            destinationFolder: destinationFolder,
            conflictPolicy: conflictPolicy
        ))
    }

    public func planMoveToFolder(
        _ urls: [URL],
        destinationFolder: URL,
        conflictPolicy: MoveConflictPolicy
    ) -> BatchMovePlan {
        let existingURLs = (try? fileSystem.directoryContents(at: destinationFolder)) ?? []
        var reservedPaths = Set(existingURLs.map(normalizedPath))
        var proposals: [BatchMoveProposal] = []
        var failures: [BatchFileFailure] = []

        for url in urls {
            guard fileSystem.fileExists(at: url) else {
                failures.append(BatchFileFailure(url: url, reason: .sourceMissing))
                continue
            }

            var destination = destinationFolder.appendingPathComponent(url.lastPathComponent)
            if reservedPaths.contains(normalizedPath(destination)) {
                switch conflictPolicy {
                case .skip:
                    failures.append(BatchFileFailure(url: url, reason: .destinationExists))
                    continue
                case .keepBoth:
                    destination = nextAvailableURL(for: destination, reservedPaths: reservedPaths)
                }
            }

            reservedPaths.insert(normalizedPath(destination))
            proposals.append(BatchMoveProposal(source: url, destination: destination))
        }

        return BatchMovePlan(proposals: proposals, failures: failures)
    }

    public func executeMovePlan(_ plan: BatchMovePlan) -> BatchOperationResult {
        var succeeded: [URL] = []
        var failures = plan.failures
        var destinationPaths: Set<String> = []

        for proposal in plan.proposals {
            guard fileSystem.fileExists(at: proposal.source) else {
                failures.append(BatchFileFailure(url: proposal.source, reason: .sourceMissing))
                continue
            }

            let destinationPath = normalizedPath(proposal.destination)
            guard destinationPaths.insert(destinationPath).inserted else {
                failures.append(BatchFileFailure(url: proposal.source, reason: .duplicateDestination))
                continue
            }

            guard !fileSystem.fileExists(at: proposal.destination) else {
                failures.append(BatchFileFailure(url: proposal.source, reason: .destinationExists))
                continue
            }

            do {
                try fileSystem.moveItem(at: proposal.source, to: proposal.destination)
                succeeded.append(proposal.source)
            } catch {
                failures.append(BatchFileFailure(url: proposal.source, reason: .moveFailed(error.localizedDescription)))
            }
        }

        return BatchOperationResult(succeeded: succeeded, failures: failures)
    }

    public func planBatchRename(
        urls: [URL],
        baseName: String,
        startNumber: Int,
        padding: Int
    ) -> BatchRenamePlan {
        let trimmedBaseName = baseName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedBaseName.isEmpty else {
            return BatchRenamePlan(
                proposals: [],
                failures: urls.map { BatchFileFailure(url: $0, reason: .emptyName) }
            )
        }
        guard isValidFileBaseName(trimmedBaseName) else {
            return BatchRenamePlan(
                proposals: [],
                failures: urls.map { BatchFileFailure(url: $0, reason: .invalidName) }
            )
        }

        let selectedSources = Set(urls.map { normalizedPath($0) })
        var proposals: [RenameProposal] = []
        var failures: [BatchFileFailure] = []
        var destinationOwners: [String: URL] = [:]

        for (offset, url) in urls.enumerated() {
            let number = startNumber + offset
            let destination = renameDestination(
                for: url,
                baseName: trimmedBaseName,
                number: number,
                padding: padding
            )
            proposals.append(RenameProposal(source: url, destination: destination))

            let destinationPath = normalizedPath(destination)
            if let firstSource = destinationOwners[destinationPath], normalizedPath(firstSource) != normalizedPath(url) {
                failures.append(BatchFileFailure(url: url, reason: .duplicateDestination))
                continue
            }
            destinationOwners[destinationPath] = url

            if fileSystem.fileExists(at: destination),
               !selectedSources.contains(destinationPath),
               destinationPath != normalizedPath(url) {
                failures.append(BatchFileFailure(url: url, reason: .destinationExists))
            }
        }

        return BatchRenamePlan(proposals: proposals, failures: failures)
    }

    public func executeRenamePlan(_ plan: BatchRenamePlan) -> BatchOperationResult {
        guard plan.failures.isEmpty else {
            return BatchOperationResult(failures: plan.failures)
        }

        let activeProposals = plan.proposals.filter {
            normalizedPath($0.source) != normalizedPath($0.destination)
        }
        let sourcePaths = Set(activeProposals.map { normalizedPath($0.source) })
        var destinationPaths: Set<String> = []
        var failures: [BatchFileFailure] = []

        for proposal in activeProposals {
            guard fileSystem.fileExists(at: proposal.source) else {
                failures.append(BatchFileFailure(url: proposal.source, reason: .sourceMissing))
                continue
            }

            let destinationPath = normalizedPath(proposal.destination)
            guard destinationPaths.insert(destinationPath).inserted else {
                failures.append(BatchFileFailure(url: proposal.source, reason: .duplicateDestination))
                continue
            }

            if fileSystem.fileExists(at: proposal.destination),
               !sourcePaths.contains(destinationPath) {
                failures.append(BatchFileFailure(url: proposal.source, reason: .destinationExists))
            }
        }

        guard failures.isEmpty else {
            return BatchOperationResult(failures: failures)
        }

        var journal: [RenameJournalEntry] = []
        for proposal in activeProposals {
            let temporaryURL = temporaryURL(nextTo: proposal.source)
            do {
                try fileSystem.moveItem(at: proposal.source, to: temporaryURL)
                journal.append(RenameJournalEntry(
                    proposal: proposal,
                    temporaryURL: temporaryURL,
                    location: .temporary
                ))
            } catch {
                let recoveryFailures = restoreOriginals(from: &journal)
                return BatchOperationResult(
                    failures: [
                        BatchFileFailure(url: proposal.source, reason: .renameFailed(error.localizedDescription))
                    ],
                    recoveryFailures: recoveryFailures
                )
            }
        }

        for index in journal.indices {
            do {
                try fileSystem.moveItem(
                    at: journal[index].temporaryURL,
                    to: journal[index].proposal.destination
                )
                journal[index].location = .destination
            } catch {
                failures.append(BatchFileFailure(
                    url: journal[index].proposal.source,
                    reason: .renameFailed(error.localizedDescription)
                ))
                var recoveryFailures = reverseCommittedDestinations(in: &journal)
                recoveryFailures.append(contentsOf: restoreOriginals(from: &journal))
                return BatchOperationResult(
                    failures: failures,
                    recoveryFailures: recoveryFailures
                )
            }
        }

        return BatchOperationResult(succeeded: plan.proposals.map(\.source))
    }

    private func renameDestination(for url: URL, baseName: String, number: Int, padding: Int) -> URL {
        let formattedNumber: String
        if padding > 0 {
            formattedNumber = String(format: "%0\(padding)d", number)
        } else {
            formattedNumber = "\(number)"
        }

        let name = "\(baseName) \(formattedNumber)"
        var destination = url.deletingLastPathComponent().appendingPathComponent(name)
        let pathExtension = url.pathExtension
        if !pathExtension.isEmpty {
            destination = destination.appendingPathExtension(pathExtension)
        }
        return destination
    }

    private func nextAvailableURL(for original: URL, reservedPaths: Set<String>) -> URL {
        let folder = original.deletingLastPathComponent()
        let pathExtension = original.pathExtension
        let baseName = original.deletingPathExtension().lastPathComponent

        var index = 1
        while true {
            let suffix = index == 1 ? " copy" : " copy \(index)"
            var candidate = folder.appendingPathComponent("\(baseName)\(suffix)")
            if !pathExtension.isEmpty {
                candidate = candidate.appendingPathExtension(pathExtension)
            }
            if !reservedPaths.contains(normalizedPath(candidate)),
               !fileSystem.fileExists(at: candidate) {
                return candidate
            }
            index += 1
        }
    }

    private func temporaryURL(nextTo url: URL) -> URL {
        let folder = url.deletingLastPathComponent()
        var candidate: URL
        repeat {
            candidate = folder.appendingPathComponent(".batch-rename-\(UUID().uuidString).tmp")
        } while fileSystem.fileExists(at: candidate)
        return candidate
    }

    private func reverseCommittedDestinations(
        in journal: inout [RenameJournalEntry]
    ) -> [BatchRecoveryFailure] {
        var recoveryFailures: [BatchRecoveryFailure] = []
        for index in journal.indices.reversed() where journal[index].location == .destination {
            do {
                try fileSystem.moveItem(
                    at: journal[index].proposal.destination,
                    to: journal[index].temporaryURL
                )
                journal[index].location = .temporary
            } catch {
                recoveryFailures.append(BatchRecoveryFailure(
                    expectedURL: journal[index].proposal.source,
                    actualURL: journal[index].proposal.destination,
                    reason: error.localizedDescription
                ))
            }
        }
        return recoveryFailures
    }

    private func restoreOriginals(from journal: inout [RenameJournalEntry]) -> [BatchRecoveryFailure] {
        var recoveryFailures: [BatchRecoveryFailure] = []
        for index in journal.indices.reversed() where journal[index].location == .temporary {
            do {
                try fileSystem.moveItem(
                    at: journal[index].temporaryURL,
                    to: journal[index].proposal.source
                )
                journal[index].location = .original
            } catch {
                let recoveryLocation = relocateStrandedTemporary(
                    journal[index].temporaryURL,
                    for: journal[index].proposal.source,
                    after: error
                )
                recoveryFailures.append(BatchRecoveryFailure(
                    expectedURL: journal[index].proposal.source,
                    actualURL: recoveryLocation.actualURL,
                    reason: recoveryLocation.reason
                ))
            }
        }
        return recoveryFailures
    }

    private func relocateStrandedTemporary(
        _ temporaryURL: URL,
        for originalURL: URL,
        after rollbackError: Error
    ) -> (actualURL: URL, reason: String) {
        let recoveryURL = nextRecoveryURL(for: originalURL)
        do {
            try fileSystem.moveItem(at: temporaryURL, to: recoveryURL)
            return (recoveryURL, rollbackError.localizedDescription)
        } catch {
            return (
                temporaryURL,
                "\(rollbackError.localizedDescription); recovery relocation failed: \(error.localizedDescription)"
            )
        }
    }

    private func nextRecoveryURL(for originalURL: URL) -> URL {
        let folder = originalURL.deletingLastPathComponent()
        let baseName = originalURL.deletingPathExtension().lastPathComponent
        let pathExtension = originalURL.pathExtension
        var candidate: URL
        repeat {
            candidate = folder.appendingPathComponent(
                "\(baseName) batch-rename-recovery-\(UUID().uuidString)"
            )
            if !pathExtension.isEmpty {
                candidate = candidate.appendingPathExtension(pathExtension)
            }
        } while fileSystem.fileExists(at: candidate)
        return candidate
    }

    private func isValidFileBaseName(_ name: String) -> Bool {
        name != "." &&
        name != ".." &&
        !name.contains("/") &&
        !name.contains(":") &&
        !name.contains("\0")
    }

    private func normalizedPath(_ url: URL) -> String {
        url.standardizedFileURL.path
    }
}

private struct RenameJournalEntry {
    enum Location {
        case original
        case temporary
        case destination
    }

    let proposal: RenameProposal
    let temporaryURL: URL
    var location: Location
}
