import Foundation
import UniformTypeIdentifiers

public enum SupportedImageFormat: String, CaseIterable, Sendable, Hashable {
    case jpeg
    case png
    case gif
    case tiff
    case bmp
    case heic
    case heif
    case webp
    case avif
    case svg

    public init?(fileExtension: String) {
        switch fileExtension.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: ".")) {
        case "jpg", "jpeg":
            self = .jpeg
        case "png":
            self = .png
        case "gif":
            self = .gif
        case "tif", "tiff":
            self = .tiff
        case "bmp":
            self = .bmp
        case "heic":
            self = .heic
        case "heif":
            self = .heif
        case "webp":
            self = .webp
        case "avif":
            self = .avif
        case "svg":
            self = .svg
        default:
            return nil
        }
    }

    public var canAttemptSafeWrite: Bool {
        switch self {
        case .jpeg, .png, .tiff, .bmp, .heic, .heif:
            return true
        case .gif, .webp, .avif, .svg:
            return false
        }
    }

    public var contentType: UTType? {
        switch self {
        case .jpeg:
            return .jpeg
        case .png:
            return .png
        case .gif:
            return .gif
        case .tiff:
            return .tiff
        case .bmp:
            return .bmp
        case .heic:
            return .heic
        case .heif:
            return .heif
        case .webp:
            return UTType.webP
        case .avif:
            return UTType(filenameExtension: "avif")
        case .svg:
            return UTType.svg
        }
    }

    public var imageIOTypeIdentifier: String? {
        switch self {
        case .avif:
            return "public.avif"
        default:
            return contentType?.identifier
        }
    }
}
