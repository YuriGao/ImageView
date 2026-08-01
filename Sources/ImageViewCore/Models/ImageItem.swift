import Foundation

public struct ImageItem: Equatable, Identifiable, Sendable {
    public let id: URL
    public let url: URL
    public let format: SupportedImageFormat
    public let contentModificationDate: Date
    public let fileSize: Int64
    public let pairedRawURL: URL?

    public init(
        url: URL,
        format: SupportedImageFormat,
        contentModificationDate: Date = .distantPast,
        fileSize: Int64 = 0,
        pairedRawURL: URL? = nil
    ) {
        self.id = url
        self.url = url
        self.format = format
        self.contentModificationDate = contentModificationDate
        self.fileSize = fileSize
        self.pairedRawURL = pairedRawURL
    }

    public var displayFilename: String {
        guard let pairedRawURL else { return url.lastPathComponent }
        return "\(pairedRawURL.lastPathComponent) / \(url.lastPathComponent)"
    }

    public func represents(_ candidateURL: URL) -> Bool {
        let candidate = candidateURL.standardizedFileURL
        return url.standardizedFileURL == candidate
            || pairedRawURL?.standardizedFileURL == candidate
    }
}
