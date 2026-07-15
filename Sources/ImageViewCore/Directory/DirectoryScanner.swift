import Foundation

public final class DirectoryScanner: @unchecked Sendable {
    private let fileManager: FileManager

    public init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
    }

    public func scan(containing openedFile: URL) async throws -> [ImageItem] {
        let directory = openedFile.deletingLastPathComponent()
        return try await scan(directory: directory, openedFile: openedFile)
    }

    public func scan(folder directory: URL) async throws -> [ImageItem] {
        try await scan(directory: directory, openedFile: nil)
    }

    private func scan(directory: URL, openedFile: URL?) async throws -> [ImageItem] {
        try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    let resourceKeys: Set<URLResourceKey> = [
                        .isRegularFileKey,
                        .contentModificationDateKey,
                        .fileSizeKey
                    ]
                    let urls = try self.fileManager.contentsOfDirectory(
                        at: directory,
                        includingPropertiesForKeys: Array(resourceKeys),
                        options: [.skipsHiddenFiles]
                    )

                    let items = urls.compactMap { url -> ImageItem? in
                        guard let values = try? url.resourceValues(forKeys: resourceKeys),
                              values.isRegularFile == true,
                              let format = SupportedImageFormat(fileExtension: url.pathExtension) else {
                            return nil
                        }
                        let itemURL = if let openedFile,
                                         url.standardizedFileURL.path == openedFile.standardizedFileURL.path {
                            openedFile
                        } else {
                            url
                        }
                        return ImageItem(
                            url: itemURL,
                            format: format,
                            contentModificationDate: values.contentModificationDate ?? .distantPast,
                            fileSize: Int64(values.fileSize ?? 0)
                        )
                    }
                    .sorted { NaturalSort.compare($0.url.lastPathComponent, $1.url.lastPathComponent) }

                    continuation.resume(returning: items)
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }
}
