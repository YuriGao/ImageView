import Combine
import Foundation
import ImageViewCore
import UniformTypeIdentifiers

enum FileAssociationRowError: Equatable {
    case unsupportedContentType
    case service(String)
}

struct FileAssociationRowState: Equatable {
    var defaultApplicationName: String?
    var isImageViewDefault = false
    var error: FileAssociationRowError?
}

enum FileAssociationSummary: Equatable {
    case success(count: Int)
    case partialSuccess(succeeded: Int, failed: Int)
    case failure(count: Int)
    case invalidApplicationBundle
}

@MainActor
final class FileAssociationSettingsModel: ObservableObject {
    static let commonFormats: [SupportedImageFormat] = [.jpeg, .png, .gif, .webp, .heic]
    static let allFormats: [SupportedImageFormat] = [
        .jpeg, .png, .gif, .webp, .heic,
        .tiff, .bmp, .heif, .avif, .svg
    ]

    @Published private(set) var selectedFormats: Set<SupportedImageFormat> = []
    @Published private(set) var rows: [SupportedImageFormat: FileAssociationRowState] = [:]
    @Published private(set) var showsAllFormats = false
    @Published private(set) var isApplying = false
    @Published private(set) var summary: FileAssociationSummary?

    var visibleFormats: [SupportedImageFormat] {
        showsAllFormats ? Self.allFormats : Self.commonFormats
    }

    var canApply: Bool { !selectedFormats.isEmpty && !isApplying }

    private let service: DefaultApplicationServicing
    private let applicationURL: () -> URL?

    init(
        service: DefaultApplicationServicing,
        applicationURL: @escaping () -> URL?
    ) {
        self.service = service
        self.applicationURL = applicationURL
    }

    func toggleSelection(for format: SupportedImageFormat) {
        if selectedFormats.contains(format) {
            selectedFormats.remove(format)
        } else {
            selectedFormats.insert(format)
        }
        summary = nil
    }

    func selectCommonFormats() {
        selectedFormats.formUnion(Self.commonFormats)
        summary = nil
    }

    func setShowsAllFormats(_ showsAll: Bool) {
        showsAllFormats = showsAll
    }

    func refreshStatuses() {
        let imageViewURL = applicationURL()?.standardizedFileURL
        for format in Self.allFormats {
            guard let contentType = format.contentType else {
                rows[format] = FileAssociationRowState()
                continue
            }
            let defaultURL = service.defaultApplicationURL(for: contentType)?.standardizedFileURL
            rows[format] = FileAssociationRowState(
                defaultApplicationName: defaultURL?.deletingPathExtension().lastPathComponent,
                isImageViewDefault: imageViewURL.map { defaultURL == $0 } ?? false,
                error: rows[format]?.error
            )
        }
    }

    func applySelectedFormats() async {
        guard canApply else { return }
        guard let appURL = applicationURL(), appURL.pathExtension.lowercased() == "app" else {
            summary = .invalidApplicationBundle
            return
        }

        isApplying = true
        summary = nil
        var succeeded = 0
        var failed = 0
        let formats = Self.allFormats.filter(selectedFormats.contains)

        for format in formats {
            guard let contentType = format.contentType else {
                failed += 1
                rows[format, default: FileAssociationRowState()].error = .unsupportedContentType
                continue
            }
            do {
                try await service.setDefaultApplication(at: appURL, for: contentType)
                succeeded += 1
                selectedFormats.remove(format)
                rows[format, default: FileAssociationRowState()].error = nil
            } catch {
                failed += 1
                rows[format, default: FileAssociationRowState()].error = .service(error.localizedDescription)
            }
        }

        isApplying = false
        summary = failed == 0
            ? .success(count: succeeded)
            : succeeded == 0
                ? .failure(count: failed)
                : .partialSuccess(succeeded: succeeded, failed: failed)
        refreshStatuses()
    }
}
