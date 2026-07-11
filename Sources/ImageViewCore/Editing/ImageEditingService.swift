import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

public enum ImageEditingError: Error, Equatable {
    case cannotCreateContext
    case cannotCreateImage
    case unsupportedSaveFormat
    case cannotCreateDestination
    case saveFailed
}

public final class ImageEditingService {
    public init() {}

    public static func writableSaveFormats() -> [SupportedImageFormat] {
        [.png, .jpeg, .tiff, .bmp, .heic, .heif].filter { format in
            guard let uti = uti(for: format) else { return false }
            let destinationTypes = CGImageDestinationCopyTypeIdentifiers() as? [String] ?? []
            return destinationTypes.contains(uti)
        }
    }

    public func apply(_ operations: [EditOperation], to image: CGImage) throws -> CGImage {
        try operations.reduce(image) { current, operation in
            switch operation {
            case .rotateClockwise:
                return try transform(current, radians: -.pi / 2, scaleX: 1, scaleY: 1)
            case .rotateCounterClockwise:
                return try transform(current, radians: .pi / 2, scaleX: 1, scaleY: 1)
            case .mirrorHorizontal:
                return try transform(current, radians: 0, scaleX: -1, scaleY: 1)
            case .mirrorVertical:
                return try transform(current, radians: 0, scaleX: 1, scaleY: -1)
            case .crop(let rect):
                guard let cropped = current.cropping(to: rect.integral) else {
                    throw ImageEditingError.cannotCreateImage
                }
                return cropped
            }
        }
    }

    public func save(
        _ image: CGImage,
        to url: URL,
        format: SupportedImageFormat,
        metadataSourceURL: URL? = nil
    ) throws {
        guard format.canAttemptSafeWrite, let uti = Self.uti(for: format) else {
            throw ImageEditingError.unsupportedSaveFormat
        }

        let metadata = metadataSourceURL.flatMap {
            sanitizedMetadata(from: $0, for: format, outputImage: image)
        }

        let temporaryURL = url
            .deletingLastPathComponent()
            .appendingPathComponent(".\(url.lastPathComponent).imageview-tmp")
        try? FileManager.default.removeItem(at: temporaryURL)
        defer { try? FileManager.default.removeItem(at: temporaryURL) }

        guard let destination = CGImageDestinationCreateWithURL(
            temporaryURL as CFURL,
            uti as CFString,
            1,
            nil
        ) else {
            throw ImageEditingError.cannotCreateDestination
        }

        CGImageDestinationAddImage(destination, image, metadata as CFDictionary?)
        guard CGImageDestinationFinalize(destination) else {
            throw ImageEditingError.saveFailed
        }

        do {
            if FileManager.default.fileExists(atPath: url.path) {
                _ = try FileManager.default.replaceItemAt(url, withItemAt: temporaryURL)
            } else {
                try FileManager.default.moveItem(at: temporaryURL, to: url)
            }
        } catch {
            try? FileManager.default.removeItem(at: temporaryURL)
            throw error
        }
    }

    private func sanitizedMetadata(
        from sourceURL: URL,
        for format: SupportedImageFormat,
        outputImage: CGImage
    ) -> [CFString: Any]? {
        guard let source = CGImageSourceCreateWithURL(sourceURL as CFURL, nil),
              let sourceProperties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any] else {
            return nil
        }

        var properties: [CFString: Any] = [:]
        for key in Self.compatibleRootKeys {
            properties[key] = sourceProperties[key]
        }

        if Self.supportsRichMetadata(format) {
            for key in Self.compatibleMetadataDictionaryKeys {
                guard let dictionary = sourceProperties[key] as? [CFString: Any] else { continue }
                properties[key] = Self.removingStaleThumbnailFields(from: dictionary)
            }
        }

        properties[kCGImagePropertyOrientation] = 1
        properties[kCGImagePropertyPixelWidth] = outputImage.width
        properties[kCGImagePropertyPixelHeight] = outputImage.height

        if var exif = properties[kCGImagePropertyExifDictionary] as? [CFString: Any] {
            exif[kCGImagePropertyExifPixelXDimension] = outputImage.width
            exif[kCGImagePropertyExifPixelYDimension] = outputImage.height
            properties[kCGImagePropertyExifDictionary] = exif
        }

        if var tiff = properties[kCGImagePropertyTIFFDictionary] as? [CFString: Any] {
            tiff[kCGImagePropertyTIFFOrientation] = 1
            for key in Self.staleTIFFStorageKeys {
                tiff.removeValue(forKey: key)
            }
            properties[kCGImagePropertyTIFFDictionary] = tiff
        }

        return properties
    }

    private static var compatibleRootKeys: [CFString] {
        [
            kCGImagePropertyDPIWidth,
            kCGImagePropertyDPIHeight,
            kCGImagePropertyColorModel,
            kCGImagePropertyProfileName
        ]
    }

    private static var compatibleMetadataDictionaryKeys: [CFString] {
        [
            kCGImagePropertyExifDictionary,
            kCGImagePropertyExifAuxDictionary,
            kCGImagePropertyGPSDictionary,
            kCGImagePropertyTIFFDictionary,
            kCGImagePropertyIPTCDictionary
        ]
    }

    private static var staleTIFFStorageKeys: [CFString] {
        [
            kCGImagePropertyTIFFCompression,
            kCGImagePropertyTIFFPhotometricInterpretation,
            kCGImagePropertyTIFFTileWidth,
            kCGImagePropertyTIFFTileLength
        ]
    }

    private static func supportsRichMetadata(_ format: SupportedImageFormat) -> Bool {
        switch format {
        case .jpeg, .tiff, .heic, .heif:
            return true
        case .png, .bmp, .gif, .webp, .avif, .svg:
            return false
        }
    }

    private static func removingStaleThumbnailFields(from dictionary: [CFString: Any]) -> [CFString: Any] {
        dictionary.reduce(into: [CFString: Any]()) { result, entry in
            let normalizedKey = (entry.key as String).lowercased()
            guard !normalizedKey.contains("thumbnail"),
                  normalizedKey != "jpeginterchangeformat",
                  normalizedKey != "jpeginterchangeformatlength" else {
                return
            }

            if let nested = entry.value as? [CFString: Any] {
                result[entry.key] = removingStaleThumbnailFields(from: nested)
            } else {
                result[entry.key] = entry.value
            }
        }
    }

    private func transform(_ image: CGImage, radians: CGFloat, scaleX: CGFloat, scaleY: CGFloat) throws -> CGImage {
        let rotated = abs(radians) == .pi / 2
        let width = rotated ? image.height : image.width
        let height = rotated ? image.width : image.height

        guard let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: image.colorSpace ?? CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            throw ImageEditingError.cannotCreateContext
        }

        context.translateBy(x: CGFloat(width) / 2, y: CGFloat(height) / 2)
        context.rotate(by: radians)
        context.scaleBy(x: scaleX, y: scaleY)
        context.draw(
            image,
            in: CGRect(
                x: -CGFloat(image.width) / 2,
                y: -CGFloat(image.height) / 2,
                width: CGFloat(image.width),
                height: CGFloat(image.height)
            )
        )

        guard let output = context.makeImage() else {
            throw ImageEditingError.cannotCreateImage
        }
        return output
    }

    private static func uti(for format: SupportedImageFormat) -> String? {
        switch format {
        case .jpeg:
            return UTType.jpeg.identifier
        case .png:
            return UTType.png.identifier
        case .tiff:
            return UTType.tiff.identifier
        case .bmp:
            return UTType.bmp.identifier
        case .heic:
            return UTType.heic.identifier
        case .heif:
            let heifIdentifier = UTType.heif.identifier
            let destinationTypes = CGImageDestinationCopyTypeIdentifiers() as? [String] ?? []
            return destinationTypes.contains(heifIdentifier) ? heifIdentifier : nil
        case .gif, .webp, .avif, .svg:
            return nil
        }
    }
}
