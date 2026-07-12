import Foundation

public struct FolderFilter: Equatable, Sendable {
    public var searchText: String
    public var allowedFormats: Set<SupportedImageFormat>

    public init(
        searchText: String = "",
        allowedFormats: Set<SupportedImageFormat> = Set(SupportedImageFormat.allCases)
    ) {
        self.searchText = searchText
        self.allowedFormats = allowedFormats
    }
}
