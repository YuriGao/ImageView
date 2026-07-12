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
            let lhsDate = lhs.url.folderSessionContentModificationDate
            let rhsDate = rhs.url.folderSessionContentModificationDate
            if lhsDate != rhsDate {
                return lhsDate > rhsDate
            }
            return NaturalSort.compare(lhs.url.lastPathComponent, rhs.url.lastPathComponent)
        case .fileSizeDescending:
            let lhsSize = lhs.url.folderSessionFileSize
            let rhsSize = rhs.url.folderSessionFileSize
            if lhsSize != rhsSize {
                return lhsSize > rhsSize
            }
            return NaturalSort.compare(lhs.url.lastPathComponent, rhs.url.lastPathComponent)
        }
    }
}

private extension URL {
    var folderSessionContentModificationDate: Date {
        (try? resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
    }

    var folderSessionFileSize: Int64 {
        let values = try? resourceValues(forKeys: [.fileSizeKey])
        return Int64(values?.fileSize ?? 0)
    }
}
