import Foundation

public enum FolderSortMode: Equatable, Sendable {
    case nameAscending
    case modifiedDateDescending
    case fileSizeDescending

    func areInIncreasingOrder(_ lhs: ImageItem, _ rhs: ImageItem) -> Bool {
        switch self {
        case .nameAscending:
            return NaturalSort.compare(lhs.url.lastPathComponent, rhs.url.lastPathComponent)
        case .modifiedDateDescending:
            let lhsDate = lhs.contentModificationDate
            let rhsDate = rhs.contentModificationDate
            if lhsDate != rhsDate {
                return lhsDate > rhsDate
            }
            return NaturalSort.compare(lhs.url.lastPathComponent, rhs.url.lastPathComponent)
        case .fileSizeDescending:
            let lhsSize = lhs.fileSize
            let rhsSize = rhs.fileSize
            if lhsSize != rhsSize {
                return lhsSize > rhsSize
            }
            return NaturalSort.compare(lhs.url.lastPathComponent, rhs.url.lastPathComponent)
        }
    }
}
