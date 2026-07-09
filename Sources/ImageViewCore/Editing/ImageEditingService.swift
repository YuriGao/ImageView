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

    public func apply(_ operations: [EditOperation], to image: CGImage) throws -> CGImage {
        try operations.reduce(image) { current, operation in
            switch operation {
            case .rotateClockwise:
                return try transform(current, radians: .pi / 2, scaleX: 1, scaleY: 1)
            case .rotateCounterClockwise:
                return try transform(current, radians: -.pi / 2, scaleX: 1, scaleY: 1)
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

    public func save(_ image: CGImage, to url: URL, format: SupportedImageFormat) throws {
        guard format.canAttemptSafeWrite, let uti = uti(for: format) else {
            throw ImageEditingError.unsupportedSaveFormat
        }

        let temporaryURL = url
            .deletingLastPathComponent()
            .appendingPathComponent(".\(url.lastPathComponent).imageview-tmp")

        guard let destination = CGImageDestinationCreateWithURL(
            temporaryURL as CFURL,
            uti as CFString,
            1,
            nil
        ) else {
            throw ImageEditingError.cannotCreateDestination
        }

        CGImageDestinationAddImage(destination, image, nil)
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

    private func uti(for format: SupportedImageFormat) -> String? {
        switch format {
        case .jpeg:
            return UTType.jpeg.identifier
        case .png:
            return UTType.png.identifier
        case .tiff:
            return UTType.tiff.identifier
        case .bmp:
            return UTType.bmp.identifier
        case .heic, .heif:
            return UTType.heic.identifier
        case .gif, .webp, .avif, .svg:
            return nil
        }
    }
}
