import ImageViewCore
import SwiftUI

struct InspectorView: View {
    let metadata: ImageMetadata?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Info")
                .font(.system(size: 13, weight: .semibold))

            if let metadata {
                row("Format", metadata.format.displayName)
                row("Pixels", "\(metadata.pixelWidth) x \(metadata.pixelHeight)")
                row("Size", Self.fileSizeText(metadata.fileSize))
                row("Modified", Self.dateText(metadata.modifiedAt))
                if let capturedAt = metadata.capturedAt {
                    row("Captured", Self.dateText(capturedAt))
                }
                if let camera = Self.cameraText(metadata) {
                    row("Camera", camera)
                }
                row("File", metadata.url.lastPathComponent)
            } else {
                Text("No image")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }
        }
        .frame(width: 220, alignment: .topLeading)
        .padding(14)
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private func row(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.secondary)
            Text(value)
                .font(.system(size: 12))
                .lineLimit(2)
                .truncationMode(.middle)
        }
    }

    static func fileSizeText(_ bytes: Int64?) -> String {
        guard let bytes else { return "Unknown" }
        return ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }

    static func dateText(_ date: Date?) -> String {
        guard let date else { return "Unknown" }
        return date.formatted(date: .abbreviated, time: .shortened)
    }

    static func cameraText(_ metadata: ImageMetadata) -> String? {
        [metadata.cameraMake, metadata.cameraModel]
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: " ")
            .nilIfEmpty
    }
}

private extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}

private extension SupportedImageFormat {
    var displayName: String {
        switch self {
        case .jpeg:
            return "JPEG"
        case .png:
            return "PNG"
        case .gif:
            return "GIF"
        case .tiff:
            return "TIFF"
        case .bmp:
            return "BMP"
        case .heic:
            return "HEIC"
        case .heif:
            return "HEIF"
        case .webp:
            return "WebP"
        case .avif:
            return "AVIF"
        case .svg:
            return "SVG"
        }
    }
}
