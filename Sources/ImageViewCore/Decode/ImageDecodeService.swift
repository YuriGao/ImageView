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
        if format == .svg {
            if let decoded = try? decodeWithNSImage(url: url, maxPixelSize: maxPixelSize, requiresVisibleContent: true) {
                return decoded
            }

            if let decoded = try? decodeSimpleSVG(url: url, maxPixelSize: maxPixelSize) {
                return decoded
            }

            throw ImageDecodeError.cannotDecodeImage
        }

        if let decoded = try? decodeWithNSImage(url: url, maxPixelSize: maxPixelSize, requiresVisibleContent: false) {
            return decoded
        }

        throw ImageDecodeError.cannotDecodeImage
    }

    private func decodeWithNSImage(url: URL, maxPixelSize: CGFloat?, requiresVisibleContent: Bool) throws -> DecodedImage {
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

        if requiresVisibleContent && !hasVisiblePixels(cgImage) {
            throw ImageDecodeError.cannotDecodeImage
        }

        return DecodedImage(
            cgImage: cgImage,
            pixelSize: CGSize(width: cgImage.width, height: cgImage.height),
            isAnimated: false
        )
    }

    private func decodeSimpleSVG(url: URL, maxPixelSize: CGFloat?) throws -> DecodedImage {
        let data = try Data(contentsOf: url)
        let parser = SVGParser(data: data)
        guard let document = parser.parse(),
              let rect = document.rects.first else {
            throw ImageDecodeError.cannotDecodeImage
        }

        let outputSize = scaled(size: document.size, maxPixelSize: maxPixelSize)
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
        context.setFillColor(rect.fillColor)

        let xScale = CGFloat(pixelWidth) / document.size.width
        let yScale = CGFloat(pixelHeight) / document.size.height
        let scaledRect = CGRect(
            x: rect.frame.origin.x * xScale,
            y: rect.frame.origin.y * yScale,
            width: rect.frame.size.width * xScale,
            height: rect.frame.size.height * yScale
        )
        context.fill(scaledRect)

        guard let image = context.makeImage() else {
            throw ImageDecodeError.cannotDecodeImage
        }

        guard hasVisiblePixels(image) else {
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

    private func hasVisiblePixels(_ image: CGImage) -> Bool {
        guard let provider = image.dataProvider,
              let data = provider.data,
              let bytes = CFDataGetBytePtr(data) else {
            return false
        }

        let bytesPerPixel = max(1, image.bitsPerPixel / 8)
        guard bytesPerPixel >= 4 else {
            return true
        }

        for row in 0..<image.height {
            let rowStart = row * image.bytesPerRow
            for column in 0..<image.width {
                let offset = rowStart + (column * bytesPerPixel)
                if bytes[offset + 3] > 0 {
                    return true
                }
            }
        }

        return false
    }
}

private final class SVGParser: NSObject, XMLParserDelegate {
    struct Document {
        let size: CGSize
        let rects: [Rect]
    }

    struct Rect {
        let frame: CGRect
        let fillColor: CGColor
    }

    private let parser: XMLParser
    private var size: CGSize?
    private var rects: [Rect] = []

    init(data: Data) {
        parser = XMLParser(data: data)
        super.init()
        parser.delegate = self
    }

    func parse() -> Document? {
        _ = parser.parse()
        guard let size, !rects.isEmpty else {
            return nil
        }

        return Document(size: size, rects: rects)
    }

    func parser(_ parser: XMLParser,
                didStartElement elementName: String,
                namespaceURI: String?,
                qualifiedName qName: String?,
                attributes attributeDict: [String: String] = [:]) {
        if size == nil, elementName.caseInsensitiveCompare("svg") == .orderedSame {
            if let width = Self.length(from: attributeDict["width"]),
               let height = Self.length(from: attributeDict["height"]) {
                size = CGSize(width: width, height: height)
                return
            }

            if let viewBox = attributeDict["viewBox"] {
                let parts = viewBox
                    .split(whereSeparator: \.isWhitespace)
                    .compactMap { Double($0) }

                if parts.count == 4 {
                    size = CGSize(width: max(1, CGFloat(parts[2])), height: max(1, CGFloat(parts[3])))
                }
            }
            return
        }

        guard elementName.caseInsensitiveCompare("rect") == .orderedSame,
              let size,
              let width = Self.length(from: attributeDict["width"]),
              let height = Self.length(from: attributeDict["height"]),
              let fillColor = Self.color(from: attributeDict["fill"]) else {
            return
        }

        let x = Self.length(from: attributeDict["x"]) ?? 0
        let y = Self.length(from: attributeDict["y"]) ?? 0
        let frame = CGRect(x: x, y: size.height - y - height, width: width, height: height)
        rects.append(Rect(frame: frame, fillColor: fillColor))
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

    private static func color(from value: String?) -> CGColor? {
        guard let value else {
            return nil
        }

        let normalized = value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        switch normalized {
        case "red":
            return CGColor(red: 1, green: 0, blue: 0, alpha: 1)
        case "green":
            return CGColor(red: 0, green: 1, blue: 0, alpha: 1)
        case "blue":
            return CGColor(red: 0, green: 0, blue: 1, alpha: 1)
        case "black":
            return CGColor(red: 0, green: 0, blue: 0, alpha: 1)
        case "white":
            return CGColor(red: 1, green: 1, blue: 1, alpha: 1)
        default:
            return colorFromHex(normalized)
        }
    }

    private static func colorFromHex(_ value: String) -> CGColor? {
        guard value.hasPrefix("#") else {
            return nil
        }

        let hex = String(value.dropFirst())
        let expanded: String
        switch hex.count {
        case 3:
            expanded = hex.map { "\($0)\($0)" }.joined()
        case 6:
            expanded = hex
        default:
            return nil
        }

        guard let raw = Int(expanded, radix: 16) else {
            return nil
        }

        let red = CGFloat((raw >> 16) & 0xFF) / 255
        let green = CGFloat((raw >> 8) & 0xFF) / 255
        let blue = CGFloat(raw & 0xFF) / 255
        return CGColor(red: red, green: green, blue: blue, alpha: 1)
    }
}
