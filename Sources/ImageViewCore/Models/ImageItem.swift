import Foundation

public struct ImageItem: Equatable, Identifiable, Sendable {
    public let id: URL
    public let url: URL
    public let format: SupportedImageFormat
    public let contentModificationDate: Date
    public let fileSize: Int64

    public init(
        url: URL,
        format: SupportedImageFormat,
        contentModificationDate: Date = .distantPast,
        fileSize: Int64 = 0
    ) {
        self.id = url
        self.url = url
        self.format = format
        self.contentModificationDate = contentModificationDate
        self.fileSize = fileSize
    }
}
