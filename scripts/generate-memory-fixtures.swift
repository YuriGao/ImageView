import AppKit
import Foundation
import ImageIO
import UniformTypeIdentifiers

enum FixtureError: Error { case cannotCreateImage, cannotCreateDestination, cannotFinalize }

let output = URL(fileURLWithPath: CommandLine.arguments.dropFirst().first ?? "/tmp/imageview-memory-fixtures", isDirectory: true)
let manager = FileManager.default
try? manager.removeItem(at: output)
try manager.createDirectory(at: output, withIntermediateDirectories: true)

func image(width: Int, height: Int, hue: CGFloat) throws -> CGImage {
    guard let context = CGContext(
        data: nil,
        width: width,
        height: height,
        bitsPerComponent: 8,
        bytesPerRow: width * 4,
        space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    ) else { throw FixtureError.cannotCreateImage }
    context.setFillColor(NSColor(calibratedHue: hue, saturation: 0.7, brightness: 0.8, alpha: 1).cgColor)
    context.fill(CGRect(x: 0, y: 0, width: width, height: height))
    guard let result = context.makeImage() else { throw FixtureError.cannotCreateImage }
    return result
}

func write(_ image: CGImage, to url: URL, type: UTType, properties: CFDictionary? = nil) throws {
    guard let destination = CGImageDestinationCreateWithURL(url as CFURL, type.identifier as CFString, 1, nil) else {
        throw FixtureError.cannotCreateDestination
    }
    CGImageDestinationAddImage(destination, image, properties)
    guard CGImageDestinationFinalize(destination) else { throw FixtureError.cannotFinalize }
}

let smallDirectory = output.appendingPathComponent("small", isDirectory: true)
let largeDirectory = output.appendingPathComponent("large", isDirectory: true)
let animatedDirectory = output.appendingPathComponent("animated", isDirectory: true)
for directory in [smallDirectory, largeDirectory, animatedDirectory] {
    try manager.createDirectory(at: directory, withIntermediateDirectories: true)
}

let smallURL = smallDirectory.appendingPathComponent("small-512.png")
try write(try image(width: 512, height: 512, hue: 0.55), to: smallURL, type: .png)

let largeURL = largeDirectory.appendingPathComponent("large-8000.png")
try write(try image(width: 8_000, height: 8_000, hue: 0.08), to: largeURL, type: .png)

let animatedURL = animatedDirectory.appendingPathComponent("animated-24x1200.gif")
guard let animatedDestination = CGImageDestinationCreateWithURL(
    animatedURL as CFURL,
    UTType.gif.identifier as CFString,
    24,
    [kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFLoopCount: 0]] as CFDictionary
) else { throw FixtureError.cannotCreateDestination }
for frame in 0..<24 {
    let frameProperties = [
        kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFDelayTime: 0.08]
    ] as CFDictionary
    CGImageDestinationAddImage(
        animatedDestination,
        try image(width: 1_200, height: 1_200, hue: CGFloat(frame) / 24),
        frameProperties
    )
}
guard CGImageDestinationFinalize(animatedDestination) else { throw FixtureError.cannotFinalize }

let directoryURL = output.appendingPathComponent("directory-1000", isDirectory: true)
try manager.createDirectory(at: directoryURL, withIntermediateDirectories: true)
for index in 0..<1_000 {
    let destination = directoryURL.appendingPathComponent(String(format: "image-%04d.png", index))
    try manager.copyItem(at: smallURL, to: destination)
}

print(output.path)
