import Foundation

/// Serial disk reads off the main actor. Edits reuse metadata for the same file version.
public actor ImageMetadataLoader {
    public static let shared = ImageMetadataLoader()
    private struct Key: Hashable {
        let url: URL
        let version: CurrentFileVersion
    }
    private var cache: [Key: ImageMetadata] = [:]

    public init() {}

    public func metadata(for url: URL, format: SupportedImageFormat, width: Int, height: Int) throws -> ImageMetadata {
        try Task.checkCancellation()
        let version = CurrentFileVersion.read(at: url)
        let key = version.map { Key(url: url.standardizedFileURL, version: $0) }
        if let key, let cached = cache[key], cached.format == format {
            return cached.replacingDimensions(width: width, height: height)
        }
        let metadata = ImageMetadataService().metadata(for: url, format: format, pixelWidth: width, pixelHeight: height)
        try Task.checkCancellation()
        if let key, CurrentFileVersion.read(at: url) == version {
            if cache.count >= 64 { cache.removeAll(keepingCapacity: true) }
            cache[key] = metadata
        }
        return metadata
    }
}
