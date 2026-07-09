import Foundation

public final class DirectoryScanner: @unchecked Sendable {
    private let fileManager: FileManager

    public init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
    }

    public func scan(containing openedFile: URL) async throws -> [ImageItem] {
        let directory = openedFile.deletingLastPathComponent()
        let urls = try fileManager.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        )

        return urls.compactMap { url in
            guard let values = try? url.resourceValues(forKeys: [.isRegularFileKey]),
                  values.isRegularFile == true,
                  let format = SupportedImageFormat(fileExtension: url.pathExtension) else {
                return nil
            }
            let itemURL = url.standardizedFileURL.path == openedFile.standardizedFileURL.path ? openedFile : url
            return ImageItem(url: itemURL, format: format)
        }
        .sorted { NaturalSort.compare($0.url.lastPathComponent, $1.url.lastPathComponent) }
    }
}
