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

                    let scannedItems = urls.compactMap { url -> ImageItem? in
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

                    let items = Self.collapsingRawJPEGPairings(in: scannedItems)

                    continuation.resume(returning: items)
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    static func collapsingRawJPEGPairings(in items: [ImageItem]) -> [ImageItem] {
        let jpegByStem = Dictionary(grouping: items.filter { $0.format == .jpeg }) {
            pairingStem(for: $0.url)
        }
        let rawByStem = Dictionary(grouping: items.filter { $0.format == .arw }) {
            pairingStem(for: $0.url)
        }

        return items.compactMap { item in
            let stem = pairingStem(for: item.url)
            if item.format == .arw, jpegByStem[stem]?.isEmpty == false {
                return nil
            }
            guard item.format == .jpeg,
                  let jpeg = jpegByStem[stem]?.first,
                  jpeg.id == item.id,
                  let raw = rawByStem[stem]?.first else {
                return item
            }
            return ImageItem(
                url: item.url,
                format: item.format,
                contentModificationDate: item.contentModificationDate,
                fileSize: item.fileSize,
                pairedRawURL: raw.url
            )
        }
    }

    private static func pairingStem(for url: URL) -> String {
        url.deletingPathExtension().lastPathComponent.folding(
            options: [.caseInsensitive, .diacriticInsensitive],
            locale: Locale(identifier: "en_US_POSIX")
        )
    }
}
