import Foundation
import ImageIO

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
        let imageProperties = CGImageSourceCreateWithURL(url as CFURL, nil)
            .flatMap { CGImageSourceCopyPropertiesAtIndex($0, 0, nil) as? [CFString: Any] }
        let exif = imageProperties?[kCGImagePropertyExifDictionary] as? [CFString: Any]
        let tiff = imageProperties?[kCGImagePropertyTIFFDictionary] as? [CFString: Any]
        let capturedAt = (exif?[kCGImagePropertyExifDateTimeOriginal] as? String).flatMap(Self.exifDate)

        return ImageMetadata(
            url: url,
            format: format,
            pixelWidth: pixelWidth,
            pixelHeight: pixelHeight,
            fileSize: fileSize?.int64Value,
            modifiedAt: modifiedAt,
            capturedAt: capturedAt,
            cameraMake: tiff?[kCGImagePropertyTIFFMake] as? String,
            cameraModel: tiff?[kCGImagePropertyTIFFModel] as? String
        )
    }

    private static func exifDate(_ value: String) -> Date? {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy:MM:dd HH:mm:ss"
        return formatter.date(from: value)
    }
}
