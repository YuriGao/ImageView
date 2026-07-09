import Foundation

public struct ImageMetadata: Equatable, Sendable {
    public let url: URL
    public let format: SupportedImageFormat
    public let pixelWidth: Int
    public let pixelHeight: Int
    public let fileSize: Int64?
    public let modifiedAt: Date?

    public init(
        url: URL,
        format: SupportedImageFormat,
        pixelWidth: Int,
        pixelHeight: Int,
        fileSize: Int64?,
        modifiedAt: Date?
    ) {
        self.url = url
        self.format = format
        self.pixelWidth = pixelWidth
        self.pixelHeight = pixelHeight
        self.fileSize = fileSize
        self.modifiedAt = modifiedAt
    }
}
