import AppKit
import Foundation

public enum FileActionError: Error, Equatable {
    case emptyName
    case invalidBaseName
    case unsupportedRenameTarget
    case trashLocationUnavailable
    case restoreSourceMissing
    case restoreDestinationExists
}

public final class FileActions {
    private let fileManager: FileManager

    public init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
    }

    @discardableResult
    public func moveToTrash(_ url: URL) throws -> URL {
        var resultingURL: NSURL?
        try fileManager.trashItem(at: url, resultingItemURL: &resultingURL)
        guard let resultingURL else {
            throw FileActionError.trashLocationUnavailable
        }
        return resultingURL as URL
    }

    public func restoreFromTrash(_ trashedURL: URL, to originalURL: URL) throws {
        guard fileManager.fileExists(atPath: trashedURL.path) else {
            throw FileActionError.restoreSourceMissing
        }
        guard !fileManager.fileExists(atPath: originalURL.path) else {
            throw FileActionError.restoreDestinationExists
        }
        try fileManager.moveItem(at: trashedURL, to: originalURL)
    }

    public func rename(_ url: URL, to newBaseName: String) throws -> URL {
        let trimmed = newBaseName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw FileActionError.emptyName
        }
        guard trimmed != ".",
              trimmed != "..",
              !trimmed.contains("/") else {
            throw FileActionError.invalidBaseName
        }

        let ext = url.pathExtension
        guard !ext.isEmpty else {
            throw FileActionError.unsupportedRenameTarget
        }

        let parentDirectory = url.deletingLastPathComponent()
        let destination = parentDirectory
            .appendingPathComponent(trimmed)
            .appendingPathExtension(ext)
        guard destination.deletingLastPathComponent().standardizedFileURL == parentDirectory.standardizedFileURL else {
            throw FileActionError.invalidBaseName
        }
        try fileManager.moveItem(at: url, to: destination)
        return destination
    }

    public func revealInFinder(_ url: URL) {
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    public func absolutePath(for url: URL) -> String {
        url.path
    }
}
