import AppKit
import Foundation

public enum FileActionError: Error, Equatable {
    case emptyName
    case unsupportedRenameTarget
}

public final class FileActions {
    private let fileManager: FileManager

    public init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
    }

    public func moveToTrash(_ url: URL) throws {
        var resultingURL: NSURL?
        try fileManager.trashItem(at: url, resultingItemURL: &resultingURL)
    }

    public func rename(_ url: URL, to newBaseName: String) throws -> URL {
        let trimmed = newBaseName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw FileActionError.emptyName
        }

        let ext = url.pathExtension
        guard !ext.isEmpty else {
            throw FileActionError.unsupportedRenameTarget
        }

        let destination = url
            .deletingLastPathComponent()
            .appendingPathComponent(trimmed)
            .appendingPathExtension(ext)
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
