import Foundation

public final class DirectoryScanner: @unchecked Sendable {
    private let fileManager: FileManager

    public init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
    }

    public func scan(containing openedFile: URL) async throws -> [ImageItem] {
        try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    let directory = openedFile.deletingLastPathComponent()
                    let urls = try self.fileManager.contentsOfDirectory(
                        at: directory,
                        includingPropertiesForKeys: [.isRegularFileKey],
                        options: [.skipsHiddenFiles]
                    )

                    let items = urls.compactMap { url -> ImageItem? in
                        guard let values = try? url.resourceValues(forKeys: [.isRegularFileKey]),
                              values.isRegularFile == true,
                              let format = SupportedImageFormat(fileExtension: url.pathExtension) else {
                            return nil
                        }
                        let itemURL = url.standardizedFileURL.path == openedFile.standardizedFileURL.path ? openedFile : url
                        return ImageItem(url: itemURL, format: format)
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
