import Foundation

public struct ImageItem: Equatable, Identifiable, Sendable {
    public let id: URL
    public let url: URL
    public let format: SupportedImageFormat

    public init(url: URL, format: SupportedImageFormat) {
        self.id = url
        self.url = url
        self.format = format
    }
}
