import AppKit
import ImageViewCore
import SwiftUI

struct InspectorView: View {
    let metadata: ImageMetadata?
    var isDocked = false
    var onToggleDock: () -> Void = {}
    var onClose: () -> Void = {}

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text(AppStrings.text("inspector.title"))
                        .font(.system(size: 13, weight: .semibold))
                    Spacer()
                    Button(action: onToggleDock) {
                        Image(systemName: isDocked ? "pin.slash" : "pin")
                    }
                    .buttonStyle(.plain)
                    .help(AppStrings.text(isDocked ? "inspector.undock" : "inspector.dock"))
                    .accessibilityLabel(AppStrings.text(isDocked ? "inspector.undock" : "inspector.dock"))
                    Button(action: onClose) {
                        Image(systemName: "xmark")
                    }
                    .buttonStyle(.plain)
                    .help(AppStrings.text("inspector.close"))
                    .accessibilityLabel(AppStrings.text("inspector.close"))
                }

                if let metadata {
                    copyableRow(AppStrings.text("inspector.file"), metadata.url.lastPathComponent)
                    copyableRow(AppStrings.text("inspector.path"), metadata.url.path)
                    row(AppStrings.text("inspector.format"), metadata.format.displayName)
                    copyableRow(AppStrings.text("inspector.pixels"), "\(metadata.pixelWidth) x \(metadata.pixelHeight)")
                    row(AppStrings.text("inspector.size"), Self.fileSizeText(metadata.fileSize))
                    row(AppStrings.text("inspector.modified"), Self.dateText(metadata.modifiedAt))
                    if let capturedAt = metadata.capturedAt {
                        copyableRow(AppStrings.text("inspector.captured"), Self.dateText(capturedAt))
                    }
                    if let camera = Self.cameraText(metadata) {
                        row(AppStrings.text("inspector.camera"), camera)
                    }
                    if let colorSpace = metadata.colorSpace { row(AppStrings.text("inspector.colorSpace"), colorSpace) }
                    if let colorProfile = metadata.colorProfile { row(AppStrings.text("inspector.colorProfile"), colorProfile) }
                    if let bitDepth = metadata.bitDepth { row(AppStrings.text("inspector.bitDepth"), "\(bitDepth)-bit") }
                    if let orientation = metadata.orientation { row(AppStrings.text("inspector.orientation"), "\(orientation)") }
                    if let exposureTime = metadata.exposureTime {
                        row(AppStrings.text("inspector.exposureTime"), Self.exposureTimeText(exposureTime))
                    }
                    if let aperture = metadata.aperture {
                        row(AppStrings.text("inspector.aperture"), String(format: "f/%.1f", aperture))
                    }
                    if let isoSpeed = metadata.isoSpeed {
                        row(AppStrings.text("inspector.isoSpeed"), "ISO \(isoSpeed)")
                    }
                    if let focalLength = metadata.focalLength {
                        row(AppStrings.text("inspector.focalLength"), String(format: "%.1f mm", focalLength))
                    }
                    Button(AppStrings.text("inspector.reveal")) {
                        NSWorkspace.shared.activateFileViewerSelecting([metadata.url])
                    }
                    .controlSize(.small)
                } else {
                    Text(AppStrings.text("inspector.noImage"))
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
            }
            .padding(14)
        }
        .frame(width: 220, alignment: .topLeading)
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private func copyableRow(_ label: String, _ value: String) -> some View {
        HStack(alignment: .top, spacing: 6) {
            row(label, value)
            Spacer(minLength: 4)
            Button {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(value, forType: .string)
            } label: {
                Image(systemName: "doc.on.doc")
            }
            .buttonStyle(.plain)
            .help(AppStrings.text("inspector.copy"))
            .accessibilityLabel("\(AppStrings.text("inspector.copy")) \(label)")
        }
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
        guard let bytes else { return AppStrings.text("inspector.unknown") }
        return ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }

    static func dateText(_ date: Date?) -> String {
        guard let date else { return AppStrings.text("inspector.unknown") }
        return date.formatted(date: .abbreviated, time: .shortened)
    }

    static func cameraText(_ metadata: ImageMetadata) -> String? {
        [metadata.cameraMake, metadata.cameraModel]
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: " ")
            .nilIfEmpty
    }

    static func exposureTimeText(_ seconds: Double) -> String {
        guard seconds > 0 else { return AppStrings.text("inspector.unknown") }
        if seconds < 1 {
            return "1/\(Int((1 / seconds).rounded())) s"
        }
        return String(format: "%.2f s", seconds)
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
