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
    private let bundleResolver: ApplicationBundleResolving

    init(
        service: DefaultApplicationServicing,
        applicationURL: @escaping () -> URL?,
        bundleResolver: ApplicationBundleResolving = BundleApplicationResolver()
    ) {
        self.service = service
        self.applicationURL = applicationURL
        self.bundleResolver = bundleResolver
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
        let imageView = bundleResolver.validatedRunningApplication(at: applicationURL())
        for format in Self.allFormats {
            guard let contentType = format.contentType else {
                rows[format] = FileAssociationRowState()
                continue
            }
            let defaultApplication = service.defaultApplicationURL(for: contentType).flatMap(bundleResolver.application(at:))
            rows[format] = FileAssociationRowState(
                defaultApplicationName: defaultApplication?.displayName,
                isImageViewDefault: Self.isSameApplication(imageView, defaultApplication),
                error: rows[format]?.error
            )
        }
    }

    private static func isSameApplication(_ lhs: ApplicationBundleInfo?, _ rhs: ApplicationBundleInfo?) -> Bool {
        guard let lhs, let rhs else { return false }
        if let lhsIdentifier = lhs.bundleIdentifier, let rhsIdentifier = rhs.bundleIdentifier {
            return lhsIdentifier == rhsIdentifier
        }
        return lhs.url.resolvingSymlinksInPath().standardizedFileURL
            == rhs.url.resolvingSymlinksInPath().standardizedFileURL
    }

    func applySelectedFormats() async {
        guard canApply else { return }
        guard let application = bundleResolver.validatedRunningApplication(at: applicationURL()) else {
            summary = .invalidApplicationBundle
            return
        }
        let appURL = application.url

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
