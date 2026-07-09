import AppKit
import CoreGraphics
import Foundation
import ImageIO

public struct DecodedImage: @unchecked Sendable {
    public let cgImage: CGImage
    public let pixelSize: CGSize
    public let isAnimated: Bool

    public init(cgImage: CGImage, pixelSize: CGSize, isAnimated: Bool) {
        self.cgImage = cgImage
        self.pixelSize = pixelSize
        self.isAnimated = isAnimated
    }
}

public enum ImageDecodeError: Error, Equatable {
    case cannotCreateSource
    case cannotDecodeImage
}

public final class ImageDecodeService: @unchecked Sendable {
    public init() {}

    public func decode(url: URL, format: SupportedImageFormat, maxPixelSize: CGFloat? = nil) throws -> DecodedImage {
        if let source = CGImageSourceCreateWithURL(url as CFURL, nil),
           let decoded = decodeImageIO(source: source, maxPixelSize: maxPixelSize) {
            return decoded
        }

        if format == .svg || format == .webp || format == .avif {
            return try decodeWithFallback(url: url, format: format, maxPixelSize: maxPixelSize)
        }

        throw ImageDecodeError.cannotCreateSource
    }

    private func decodeImageIO(source: CGImageSource, maxPixelSize: CGFloat?) -> DecodedImage? {
        let options: [CFString: Any]
        if let maxPixelSize {
            options = [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceThumbnailMaxPixelSize: maxPixelSize
            ]
        } else {
            options = [kCGImageSourceShouldCache: false]
        }

        let image: CGImage?
        if maxPixelSize == nil {
            image = CGImageSourceCreateImageAtIndex(source, 0, options as CFDictionary)
        } else {
            image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
        }

        guard let image else {
            return nil
        }

        return DecodedImage(
            cgImage: image,
            pixelSize: CGSize(width: image.width, height: image.height),
            isAnimated: CGImageSourceGetCount(source) > 1
        )
    }

    private func decodeWithFallback(url: URL, format: SupportedImageFormat, maxPixelSize: CGFloat?) throws -> DecodedImage {
        if let decoded = try? decodeWithNSImage(url: url, maxPixelSize: maxPixelSize) {
            return decoded
        }

        if format == .svg {
            return try decodeSVGPlaceholder(url: url, maxPixelSize: maxPixelSize)
        }

        throw ImageDecodeError.cannotDecodeImage
    }

    private func decodeWithNSImage(url: URL, maxPixelSize: CGFloat?) throws -> DecodedImage {
        guard let nsImage = NSImage(contentsOf: url) else {
            throw ImageDecodeError.cannotDecodeImage
        }

        let sourceSize = normalized(size: nsImage.size)
        let outputSize = scaled(size: sourceSize, maxPixelSize: maxPixelSize)
        let pixelWidth = max(1, Int(outputSize.width.rounded(.up)))
        let pixelHeight = max(1, Int(outputSize.height.rounded(.up)))

        guard let bitmap = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: pixelWidth,
            pixelsHigh: pixelHeight,
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        ) else {
            throw ImageDecodeError.cannotDecodeImage
        }

        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
        nsImage.draw(in: CGRect(origin: .zero, size: CGSize(width: pixelWidth, height: pixelHeight)))
        NSGraphicsContext.restoreGraphicsState()

        guard let cgImage = bitmap.cgImage else {
            throw ImageDecodeError.cannotDecodeImage
        }

        return DecodedImage(
            cgImage: cgImage,
            pixelSize: CGSize(width: cgImage.width, height: cgImage.height),
            isAnimated: false
        )
    }

    private func decodeSVGPlaceholder(url: URL, maxPixelSize: CGFloat?) throws -> DecodedImage {
        let data = try Data(contentsOf: url)
        let parser = SVGSizeParser(data: data)
        guard let size = parser.parse() else {
            throw ImageDecodeError.cannotDecodeImage
        }

        let outputSize = scaled(size: size, maxPixelSize: maxPixelSize)
        let pixelWidth = max(1, Int(outputSize.width.rounded(.up)))
        let pixelHeight = max(1, Int(outputSize.height.rounded(.up)))
        let colorSpace = CGColorSpaceCreateDeviceRGB()

        guard let context = CGContext(
            data: nil,
            width: pixelWidth,
            height: pixelHeight,
            bitsPerComponent: 8,
            bytesPerRow: pixelWidth * 4,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            throw ImageDecodeError.cannotDecodeImage
        }

        context.clear(CGRect(x: 0, y: 0, width: pixelWidth, height: pixelHeight))

        guard let image = context.makeImage() else {
            throw ImageDecodeError.cannotDecodeImage
        }

        return DecodedImage(
            cgImage: image,
            pixelSize: CGSize(width: image.width, height: image.height),
            isAnimated: false
        )
    }

    private func normalized(size: CGSize) -> CGSize {
        CGSize(width: max(1, size.width), height: max(1, size.height))
    }

    private func scaled(size: CGSize, maxPixelSize: CGFloat?) -> CGSize {
        guard let maxPixelSize else {
            return normalized(size: size)
        }

        let baseSize = normalized(size: size)
        let largestDimension = max(baseSize.width, baseSize.height)
        guard largestDimension > maxPixelSize else {
            return baseSize
        }

        let scale = maxPixelSize / largestDimension
        return CGSize(width: max(1, baseSize.width * scale), height: max(1, baseSize.height * scale))
    }
}

private final class SVGSizeParser: NSObject, XMLParserDelegate {
    private let parser: XMLParser
    private var size: CGSize?

    init(data: Data) {
        parser = XMLParser(data: data)
        super.init()
        parser.delegate = self
    }

    func parse() -> CGSize? {
        _ = parser.parse()
        return size
    }

    func parser(_ parser: XMLParser,
                didStartElement elementName: String,
                namespaceURI: String?,
                qualifiedName qName: String?,
                attributes attributeDict: [String: String] = [:]) {
        guard size == nil, elementName.caseInsensitiveCompare("svg") == .orderedSame else {
            return
        }

        if let width = Self.length(from: attributeDict["width"]),
           let height = Self.length(from: attributeDict["height"]) {
            size = CGSize(width: width, height: height)
            parser.abortParsing()
            return
        }

        if let viewBox = attributeDict["viewBox"] {
            let parts = viewBox
                .split(whereSeparator: \.isWhitespace)
                .compactMap { Double($0) }

            if parts.count == 4 {
                size = CGSize(width: max(1, CGFloat(parts[2])), height: max(1, CGFloat(parts[3])))
                parser.abortParsing()
            }
        }
    }

    private static func length(from value: String?) -> CGFloat? {
        guard let value else {
            return nil
        }

        let filtered = value.filter { $0.isNumber || $0 == "." }
        guard let numericValue = Double(filtered), numericValue > 0 else {
            return nil
        }

        return CGFloat(numericValue)
    }
}
