import Darwin
import Foundation

public struct CurrentFileVersion: Equatable, Hashable, Sendable {
    public let device: UInt64
    public let inode: UInt64
    public let fileSize: Int64
    public let modificationNanoseconds: Int64
    public let changeNanoseconds: Int64

    public init(
        device: UInt64,
        inode: UInt64,
        fileSize: Int64,
        modificationNanoseconds: Int64,
        changeNanoseconds: Int64
    ) {
        self.device = device
        self.inode = inode
        self.fileSize = fileSize
        self.modificationNanoseconds = modificationNanoseconds
        self.changeNanoseconds = changeNanoseconds
    }

    public static func read(at url: URL) -> CurrentFileVersion? {
        guard FileManager.default.isReadableFile(atPath: url.path) else {
            return nil
        }

        var fileStatus = Darwin.stat()
        let result = url.withUnsafeFileSystemRepresentation { path -> Int32 in
            guard let path else { return -1 }
            return stat(path, &fileStatus)
        }
        guard result == 0,
              let modificationNanoseconds = timestampNanoseconds(fileStatus.st_mtimespec),
              let changeNanoseconds = timestampNanoseconds(fileStatus.st_ctimespec) else {
            return nil
        }

        return CurrentFileVersion(
            device: UInt64(truncatingIfNeeded: fileStatus.st_dev),
            inode: UInt64(truncatingIfNeeded: fileStatus.st_ino),
            fileSize: Int64(fileStatus.st_size),
            modificationNanoseconds: modificationNanoseconds,
            changeNanoseconds: changeNanoseconds
        )
    }

    private static func timestampNanoseconds(_ timestamp: timespec) -> Int64? {
        guard let seconds = Int64(exactly: timestamp.tv_sec),
              let nanoseconds = Int64(exactly: timestamp.tv_nsec),
              nanoseconds >= 0,
              nanoseconds < 1_000_000_000 else {
            return nil
        }

        let (scaledSeconds, multiplyOverflow) = seconds.multipliedReportingOverflow(by: 1_000_000_000)
        guard !multiplyOverflow else { return nil }
        let (combined, addOverflow) = scaledSeconds.addingReportingOverflow(nanoseconds)
        return addOverflow ? nil : combined
    }
}
