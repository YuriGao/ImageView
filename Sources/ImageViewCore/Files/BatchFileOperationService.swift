import Foundation

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

    public init(succeeded: [URL] = [], failures: [BatchFileFailure] = []) {
        self.succeeded = succeeded
        self.failures = failures
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
    private let fileManager: FileManager

    public init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
    }

    public func moveToTrash(_ urls: [URL]) -> BatchOperationResult {
        var succeeded: [URL] = []
        var failures: [BatchFileFailure] = []

        for url in urls {
            do {
                guard fileManager.fileExists(atPath: url.path) else {
                    failures.append(BatchFileFailure(url: url, reason: .sourceMissing))
                    continue
                }
                var resultingURL: NSURL?
                try fileManager.trashItem(at: url, resultingItemURL: &resultingURL)
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
        let existingURLs = (try? fileManager.contentsOfDirectory(
            at: destinationFolder,
            includingPropertiesForKeys: nil
        )) ?? []
        var reservedPaths = Set(existingURLs.map(normalizedPath))
        var proposals: [BatchMoveProposal] = []
        var failures: [BatchFileFailure] = []

        for url in urls {
            guard fileManager.fileExists(atPath: url.path) else {
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
            guard fileManager.fileExists(atPath: proposal.source.path) else {
                failures.append(BatchFileFailure(url: proposal.source, reason: .sourceMissing))
                continue
            }

            let destinationPath = normalizedPath(proposal.destination)
            guard destinationPaths.insert(destinationPath).inserted else {
                failures.append(BatchFileFailure(url: proposal.source, reason: .duplicateDestination))
                continue
            }

            guard !fileManager.fileExists(atPath: proposal.destination.path) else {
                failures.append(BatchFileFailure(url: proposal.source, reason: .destinationExists))
                continue
            }

            do {
                try fileManager.moveItem(at: proposal.source, to: proposal.destination)
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

            if fileManager.fileExists(atPath: destination.path),
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
            guard fileManager.fileExists(atPath: proposal.source.path) else {
                failures.append(BatchFileFailure(url: proposal.source, reason: .sourceMissing))
                continue
            }

            let destinationPath = normalizedPath(proposal.destination)
            guard destinationPaths.insert(destinationPath).inserted else {
                failures.append(BatchFileFailure(url: proposal.source, reason: .duplicateDestination))
                continue
            }

            if fileManager.fileExists(atPath: proposal.destination.path),
               !sourcePaths.contains(destinationPath) {
                failures.append(BatchFileFailure(url: proposal.source, reason: .destinationExists))
            }
        }

        guard failures.isEmpty else {
            return BatchOperationResult(failures: failures)
        }

        var temporaryMoves: [(proposal: RenameProposal, temporaryURL: URL)] = []
        for proposal in activeProposals {
            let temporaryURL = temporaryURL(nextTo: proposal.source)
            do {
                try fileManager.moveItem(at: proposal.source, to: temporaryURL)
                temporaryMoves.append((proposal, temporaryURL))
            } catch {
                restoreTemporaryMoves(temporaryMoves)
                return BatchOperationResult(failures: [
                    BatchFileFailure(url: proposal.source, reason: .renameFailed(error.localizedDescription))
                ])
            }
        }

        var succeeded = plan.proposals.map(\.source)
        for move in temporaryMoves {
            do {
                try fileManager.moveItem(at: move.temporaryURL, to: move.proposal.destination)
            } catch {
                try? fileManager.moveItem(at: move.temporaryURL, to: move.proposal.source)
                succeeded.removeAll { normalizedPath($0) == normalizedPath(move.proposal.source) }
                failures.append(BatchFileFailure(url: move.proposal.source, reason: .renameFailed(error.localizedDescription)))
            }
        }

        return BatchOperationResult(succeeded: succeeded, failures: failures)
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
               !fileManager.fileExists(atPath: candidate.path) {
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
        } while fileManager.fileExists(atPath: candidate.path)
        return candidate
    }

    private func restoreTemporaryMoves(_ moves: [(proposal: RenameProposal, temporaryURL: URL)]) {
        for move in moves.reversed() {
            try? fileManager.moveItem(at: move.temporaryURL, to: move.proposal.source)
        }
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
