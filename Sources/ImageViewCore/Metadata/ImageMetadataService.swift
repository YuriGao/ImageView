import Foundation

public struct ImageMetadataService {
    private let fileManager: FileManager

    public init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
    }

    public func metadata(
        for url: URL,
        format: SupportedImageFormat,
        pixelWidth: Int,
        pixelHeight: Int
    ) -> ImageMetadata {
        let attributes = try? fileManager.attributesOfItem(atPath: url.path)
        let fileSize = attributes?[.size] as? NSNumber
        let modifiedAt = attributes?[.modificationDate] as? Date

        return ImageMetadata(
            url: url,
            format: format,
            pixelWidth: pixelWidth,
            pixelHeight: pixelHeight,
            fileSize: fileSize?.int64Value,
            modifiedAt: modifiedAt
        )
    }
}
