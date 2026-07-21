import AppKit
import CoreGraphics
import Foundation
import ImageIO

public struct AnimatedFrame: @unchecked Sendable {
    public let cgImage: CGImage
    public let duration: TimeInterval

    public init(cgImage: CGImage, duration: TimeInterval) {
        self.cgImage = cgImage
        self.duration = duration
    }
}

public final class AnimatedFrameSource: @unchecked Sendable {
    public let frameCount: Int
    private let frameLoader: (Int) -> AnimatedFrame?

    public init(frameCount: Int, frameLoader: @escaping (Int) -> AnimatedFrame?) {
        self.frameCount = max(0, frameCount)
        self.frameLoader = frameLoader
    }

    public func frame(at index: Int) -> AnimatedFrame? {
        guard (0..<frameCount).contains(index) else { return nil }
        return frameLoader(index)
    }
}

public struct DecodedImage: @unchecked Sendable {
    public let cgImage: CGImage
    public let pixelSize: CGSize
    public let isAnimated: Bool
    public let animationFrames: [AnimatedFrame]
    public let animationFrameSource: AnimatedFrameSource?

    public init(
        cgImage: CGImage,
        pixelSize: CGSize,
        isAnimated: Bool,
        animationFrames: [AnimatedFrame] = [],
        animationFrameSource: AnimatedFrameSource? = nil
    ) {
        self.cgImage = cgImage
        self.pixelSize = pixelSize
        self.isAnimated = isAnimated
        self.animationFrames = animationFrames
        self.animationFrameSource = animationFrameSource
    }

    public var decodedByteCost: Int {
        animationFrames.reduce(Self.saturatedByteCost(of: cgImage)) { cost, frame in
            Self.saturatedSum(cost, Self.saturatedByteCost(of: frame.cgImage))
        }
    }

    static func saturatedByteCost(bytesPerRow: Int, height: Int) -> Int {
        let (cost, overflow) = bytesPerRow.multipliedReportingOverflow(by: height)
        return overflow ? Int.max : max(0, cost)
    }

    static func saturatedSum(_ lhs: Int, _ rhs: Int) -> Int {
        let (sum, overflow) = lhs.addingReportingOverflow(rhs)
        return overflow ? Int.max : max(0, sum)
    }

    private static func saturatedByteCost(of image: CGImage) -> Int {
        saturatedByteCost(bytesPerRow: image.bytesPerRow, height: image.height)
    }
}

public enum ImageDecodeError: Error, Equatable {
    case cannotCreateSource
    case cannotDecodeImage
}

public final class ImageDecodeService: @unchecked Sendable {
    private static let defaultAnimationByteLimit = 128 * 1024 * 1024

    private let animationByteLimit: Int

    public init() {
        animationByteLimit = Self.defaultAnimationByteLimit
    }

    init(animationByteLimit: Int) {
        self.animationByteLimit = max(0, animationByteLimit)
    }

    public static func requiresDownsampledPreview(url: URL, maxPixelSize: CGFloat) -> Bool {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = (properties[kCGImagePropertyPixelWidth] as? NSNumber)?.doubleValue,
              let height = (properties[kCGImagePropertyPixelHeight] as? NSNumber)?.doubleValue else {
            return true
        }
        return max(width, height) > Double(maxPixelSize)
    }

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
                kCGImageSourceThumbnailMaxPixelSize: maxPixelSize
            ]
        } else {
            let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]
            let pixelWidth = properties?[kCGImagePropertyPixelWidth] as? NSNumber
            let pixelHeight = properties?[kCGImagePropertyPixelHeight] as? NSNumber
            let originalMaxPixelSize = max(pixelWidth?.doubleValue ?? 1, pixelHeight?.doubleValue ?? 1)
            options = [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceThumbnailMaxPixelSize: originalMaxPixelSize
            ]
        }

        let image: CGImage?
        if maxPixelSize == nil {
            image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
        } else {
            image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
        }

        guard let image else {
            return nil
        }

        let imageProperties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]
        let tiffProperties = imageProperties?[kCGImagePropertyTIFFDictionary] as? [CFString: Any]
        let orientationRaw = (imageProperties?[kCGImagePropertyOrientation] as? NSNumber)
            ?? (tiffProperties?[kCGImagePropertyTIFFOrientation] as? NSNumber)
        let orientedImage = applyOrientation(
            image,
            orientation: CGImagePropertyOrientation(rawValue: orientationRaw?.uint32Value ?? 1) ?? .up
        )

        let frameCount = CGImageSourceGetCount(source)
        let animationFrames: [AnimatedFrame]
        let animationFrameSource: AnimatedFrameSource?
        if maxPixelSize == nil, frameCount > 1 {
            let estimatedCost = estimatedAnimationByteCost(source: source)
            if let estimatedCost, estimatedCost <= animationByteLimit {
                animationFrames = decodeAnimationFrames(source: source, options: options)
                animationFrameSource = nil
            } else {
                animationFrames = []
                animationFrameSource = makeAnimationFrameSource(source: source)
            }
        } else {
            animationFrames = []
            animationFrameSource = nil
        }
        return DecodedImage(
            cgImage: orientedImage,
            pixelSize: CGSize(width: orientedImage.width, height: orientedImage.height),
            isAnimated: frameCount > 1,
            animationFrames: animationFrames,
            animationFrameSource: animationFrameSource
        )
    }

    private func applyOrientation(_ image: CGImage, orientation: CGImagePropertyOrientation) -> CGImage {
        guard orientation != .up else { return image }
        let swapsDimensions = [.left, .leftMirrored, .right, .rightMirrored].contains(orientation)
        let width = swapsDimensions ? image.height : image.width
        let height = swapsDimensions ? image.width : image.height
        guard let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: image.colorSpace ?? CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            return image
        }

        let sourceWidth = CGFloat(image.width)
        let sourceHeight = CGFloat(image.height)
        switch orientation {
        case .upMirrored:
            context.translateBy(x: sourceWidth, y: 0)
            context.scaleBy(x: -1, y: 1)
        case .down:
            context.translateBy(x: sourceWidth, y: sourceHeight)
            context.rotate(by: .pi)
        case .downMirrored:
            context.translateBy(x: 0, y: sourceHeight)
            context.scaleBy(x: 1, y: -1)
        case .left:
            context.translateBy(x: 0, y: sourceWidth)
            context.rotate(by: -.pi / 2)
        case .leftMirrored:
            context.translateBy(x: sourceHeight, y: sourceWidth)
            context.rotate(by: -.pi / 2)
            context.scaleBy(x: -1, y: 1)
        case .right:
            context.translateBy(x: sourceHeight, y: 0)
            context.rotate(by: .pi / 2)
        case .rightMirrored:
            context.translateBy(x: sourceHeight, y: 0)
            context.rotate(by: .pi / 2)
            context.scaleBy(x: -1, y: 1)
        case .up:
            break
        @unknown default:
            return image
        }
        context.draw(image, in: CGRect(x: 0, y: 0, width: sourceWidth, height: sourceHeight))
        return context.makeImage() ?? image
    }

    private func decodeAnimationFrames(
        source: CGImageSource,
        options: [CFString: Any]
    ) -> [AnimatedFrame] {
        return (0..<CGImageSourceGetCount(source)).compactMap { index -> AnimatedFrame? in
            let image = CGImageSourceCreateImageAtIndex(source, index, options as CFDictionary)
            guard let image else { return nil }
            return AnimatedFrame(cgImage: image, duration: animationDuration(source: source, index: index))
        }
    }

    private func makeAnimationFrameSource(source: CGImageSource) -> AnimatedFrameSource {
        let frameCount = CGImageSourceGetCount(source)
        let durations = (0..<frameCount).map {
            animationDuration(source: source, index: $0)
        }
        let frameOptions = [kCGImageSourceShouldCache: false] as CFDictionary
        return AnimatedFrameSource(frameCount: frameCount) { index in
            guard let image = CGImageSourceCreateImageAtIndex(source, index, frameOptions) else {
                return nil
            }
            return AnimatedFrame(cgImage: image, duration: durations[index])
        }
    }

    private func estimatedAnimationByteCost(source: CGImageSource) -> Int? {
        var totalCost = 0
        for index in 0..<CGImageSourceGetCount(source) {
            let properties = CGImageSourceCopyPropertiesAtIndex(source, index, nil) as? [CFString: Any]
            let width = (properties?[kCGImagePropertyPixelWidth] as? NSNumber)?.intValue
            let height = (properties?[kCGImagePropertyPixelHeight] as? NSNumber)?.intValue
            guard let frameCost = Self.animationFrameByteCost(width: width, height: height) else {
                return nil
            }
            let (newTotalCost, totalOverflow) = totalCost.addingReportingOverflow(frameCost)
            guard !totalOverflow else { return nil }
            totalCost = newTotalCost
            if totalCost > animationByteLimit {
                return totalCost
            }
        }
        return totalCost
    }

    static func estimatedAnimationByteCost(frameDimensions: [(Int?, Int?)]) -> Int? {
        var totalCost = 0
        for (optionalWidth, optionalHeight) in frameDimensions {
            guard let frameCost = animationFrameByteCost(width: optionalWidth, height: optionalHeight) else { return nil }
            let (newTotalCost, totalOverflow) = totalCost.addingReportingOverflow(frameCost)
            guard !totalOverflow else { return nil }
            totalCost = newTotalCost
        }
        return totalCost
    }

    private static func animationFrameByteCost(width: Int?, height: Int?) -> Int? {
        guard let width,
              let height,
              width > 0,
              height > 0 else {
            return nil
        }
        let (pixelCount, pixelOverflow) = width.multipliedReportingOverflow(by: height)
        guard !pixelOverflow else { return nil }
        let (frameCost, byteOverflow) = pixelCount.multipliedReportingOverflow(by: 4)
        return byteOverflow ? nil : frameCost
    }

    private func animationDuration(source: CGImageSource, index: Int) -> TimeInterval {
        guard let properties = CGImageSourceCopyPropertiesAtIndex(source, index, nil) as? [CFString: Any],
              let gif = properties[kCGImagePropertyGIFDictionary] as? [CFString: Any] else {
            return 0.1
        }
        let delay = (gif[kCGImagePropertyGIFUnclampedDelayTime] as? NSNumber)?.doubleValue
            ?? (gif[kCGImagePropertyGIFDelayTime] as? NSNumber)?.doubleValue
            ?? 0.1
        return max(0.02, delay)
    }

    private func decodeWithFallback(url: URL, format: SupportedImageFormat, maxPixelSize: CGFloat?) throws -> DecodedImage {
        if format == .svg {
            if let decoded = try? decodeWithNSImage(url: url, maxPixelSize: maxPixelSize, requiresVisibleContent: true) {
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
