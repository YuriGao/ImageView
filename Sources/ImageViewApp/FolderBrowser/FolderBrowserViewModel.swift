import Combine
import Foundation
import ImageViewCore

extension BatchFileFailureReason: @unchecked Sendable {}
extension BatchFileFailure: @unchecked Sendable {}
extension BatchOperationResult: @unchecked Sendable {}
extension MoveConflictPolicy: @unchecked Sendable {}
extension RenameProposal: @unchecked Sendable {}
extension BatchRenamePlan: @unchecked Sendable {}

enum FolderBrowserPresentation: Equatable {
    case loading
    case content
    case emptyFolder
    case filteredEmpty
    case loadFailed(String)
}

enum FolderItemURLMutation: Equatable {
    case removed(Set<URL>)
    case renamed([URL: URL])
}

@MainActor
final class FolderBrowserViewModel: ObservableObject {
    typealias ScanFolder = @Sendable (URL) async throws -> [ImageItem]
    typealias MoveToTrash = @Sendable ([URL]) -> BatchOperationResult
    typealias MoveToFolder = @Sendable ([URL], URL, MoveConflictPolicy) -> BatchOperationResult
    typealias PlanBatchRename = @Sendable ([URL], String, Int, Int) -> BatchRenamePlan
    typealias ExecuteRenamePlan = @Sendable (BatchRenamePlan) -> BatchOperationResult

    @Published private(set) var session: FolderSession?
    @Published private(set) var isLoading = false
    @Published private(set) var isOperating = false
    @Published private(set) var operationMessage: String?
    @Published private(set) var operationFailures: [BatchFileFailure] = []
    @Published private(set) var loadErrorMessage: String?
    private(set) var requestedFolderURL: URL?
    var onItemURLMutation: ((FolderItemURLMutation) -> Void)?

    var visibleItems: [ImageItem] {
        session?.visibleItems ?? []
    }

    var selectedItems: [ImageItem] {
        session?.selectedItems ?? []
    }

    var presentation: FolderBrowserPresentation {
        if isLoading { return .loading }
        if let loadErrorMessage { return .loadFailed(loadErrorMessage) }
        guard let session else { return .loading }
        if session.items.isEmpty { return .emptyFolder }
        if session.visibleItems.isEmpty { return .filteredEmpty }
        return .content
    }

    var searchText: String {
        get { session?.filter.searchText ?? "" }
        set { updateFilter { $0.searchText = newValue } }
    }

    private let scanFolder: ScanFolder
    private let moveToTrashOperation: MoveToTrash
    private let moveToFolderOperation: MoveToFolder
    private let planBatchRenameOperation: PlanBatchRename
    private let executeRenamePlanOperation: ExecuteRenamePlan
    nonisolated private let openFolderRequestTracker = OpenFolderRequestTracker()

    init(
        scanFolder: @escaping ScanFolder = {
            try await DirectoryScanner().scan(folder: $0)
        },
        moveToTrash: MoveToTrash? = nil,
        moveToFolder: MoveToFolder? = nil,
        planBatchRename: PlanBatchRename? = nil,
        executeRenamePlan: ExecuteRenamePlan? = nil
    ) {
        self.scanFolder = scanFolder
        self.moveToTrashOperation = moveToTrash ?? { BatchFileOperationService().moveToTrash($0) }
        self.moveToFolderOperation = moveToFolder ?? {
            BatchFileOperationService().moveToFolder($0, destinationFolder: $1, conflictPolicy: $2)
        }
        self.planBatchRenameOperation = planBatchRename ?? {
            BatchFileOperationService().planBatchRename(urls: $0, baseName: $1, startNumber: $2, padding: $3)
        }
        self.executeRenamePlanOperation = executeRenamePlan ?? {
            BatchFileOperationService().executeRenamePlan($0)
        }
    }

    func openFolder(_ folderURL: URL) async {
        requestedFolderURL = folderURL
        let requestID = openFolderRequestTracker.next()
        isLoading = true
        loadErrorMessage = nil
        operationMessage = nil
        operationFailures = []

        do {
            let items = try await scanFolder(folderURL)
            guard openFolderRequestTracker.isCurrent(requestID) else {
                return
            }
            session = FolderSession(folderURL: folderURL, items: items)
            loadErrorMessage = nil
        } catch is CancellationError {
            guard openFolderRequestTracker.isCurrent(requestID) else {
                return
            }
            isLoading = false
            loadErrorMessage = nil
            return
        } catch {
            guard openFolderRequestTracker.isCurrent(requestID) else {
                return
            }
            session = FolderSession(folderURL: folderURL, items: [])
            loadErrorMessage = String(
                format: AppStrings.text("folderBrowser.error.openFolder"),
                error.localizedDescription
            )
        }

        isLoading = false
    }

    nonisolated func invalidateOpenFolderRequest() {
        openFolderRequestTracker.invalidate()
    }

    func cancelOpenFolderRequest() {
        invalidateOpenFolderRequest()
        requestedFolderURL = nil
        isLoading = false
        loadErrorMessage = nil
    }

    func retryOpenFolder() async {
        guard let requestedFolderURL else { return }
        await openFolder(requestedFolderURL)
    }

    func clearFilters() {
        searchText = ""
        setAllowedFormats(Set(SupportedImageFormat.allCases))
    }

    func setSelection(_ selectedItemIDs: [ImageItem.ID]) {
        session?.selectedItemIDs = selectedItemIDs
    }

    func recordOpenedItem(_ item: ImageItem) {
        session?.recordOpenedItem(with: item.id)
    }

    func setSortMode(_ sortMode: FolderSortMode) {
        session?.sortMode = sortMode
    }

    func setFilter(_ filter: FolderFilter) {
        session?.filter = filter
    }

    func setAllowedFormats(_ allowedFormats: Set<SupportedImageFormat>) {
        updateFilter { $0.allowedFormats = allowedFormats }
    }

    func applyOperationResult(_ result: BatchOperationResult, removingSucceeded: Bool) {
        operationFailures = result.failures

        if removingSucceeded {
            let succeededIDs = Set(result.succeeded)
            session?.removeItems(with: succeededIDs)
            if !succeededIDs.isEmpty {
                onItemURLMutation?(.removed(succeededIDs))
            }
        }

        let failedIDs = result.failures.map(\.url)
        session?.selectedItemIDs = failedIDs
        operationMessage = message(for: result)
    }

    @discardableResult
    func moveSelectedToTrash() -> Task<Void, Never>? {
        guard !isOperating else { return nil }
        let urls = selectedItems.map(\.url)
        guard !urls.isEmpty else { return nil }
        let operation = moveToTrashOperation
        return runBatchOperation {
            operation(urls)
        } apply: { [weak self] result in
            self?.applyOperationResult(result, removingSucceeded: true)
        }
    }

    @discardableResult
    func moveSelected(to destinationFolder: URL, conflictPolicy: MoveConflictPolicy) -> Task<Void, Never>? {
        guard !isOperating else { return nil }
        let urls = selectedItems.map(\.url)
        guard !urls.isEmpty else { return nil }
        let operation = moveToFolderOperation
        return runBatchOperation {
            operation(urls, destinationFolder, conflictPolicy)
        } apply: { [weak self] result in
            self?.applyOperationResult(result, removingSucceeded: true)
        }
    }

    @discardableResult
    func renameSelected(baseName: String, startNumber: Int = 1, padding: Int = 2) -> Task<Void, Never>? {
        guard !isOperating else { return nil }
        let urls = selectedItems.map(\.url)
        guard !urls.isEmpty else { return nil }
        let planOperation = planBatchRenameOperation
        let executeOperation = executeRenamePlanOperation
        return runBatchOperation {
            let plan = planOperation(urls, baseName, startNumber, padding)
            let result = plan.isExecutable ? executeOperation(plan) : BatchOperationResult(failures: plan.failures)
            return BatchRenameOperation(plan: plan, result: result)
        } apply: { [weak self] operation in
            self?.applyRenameResult(operation.result, plan: operation.plan)
        }
    }

    private func runBatchOperation<Value: Sendable>(
        _ operation: @escaping @Sendable () -> Value,
        apply: @escaping @MainActor (Value) -> Void
    ) -> Task<Void, Never> {
        isOperating = true
        operationFailures = []
        operationMessage = nil

        return Task { [weak self] in
            let value = await Task.detached(priority: .userInitiated) {
                operation()
            }.value
            guard let self else { return }
            apply(value)
            self.isOperating = false
        }
    }

    private func updateFilter(_ update: (inout FolderFilter) -> Void) {
        guard var filter = session?.filter else {
            return
        }
        update(&filter)
        session?.filter = filter
    }

    private func message(for result: BatchOperationResult) -> String? {
        switch (result.succeeded.count, result.failures.count) {
        case (0, 0):
            return nil
        case (_, 0):
            return String(format: AppStrings.text("folderBrowser.operation.succeeded"), result.succeeded.count)
        case (0, _):
            return String(format: AppStrings.text("folderBrowser.operation.failed"), result.failures.count)
        default:
            return String(
                format: AppStrings.text("folderBrowser.operation.succeededAndFailed"),
                result.succeeded.count,
                result.failures.count
            )
        }
    }

    private func applyRenameResult(_ result: BatchOperationResult, plan: BatchRenamePlan) {
        operationFailures = result.failures

        let succeededSources = Set(result.succeeded)
        let successfulDestinationsBySource = Dictionary(
            uniqueKeysWithValues: plan.proposals
                .filter { succeededSources.contains($0.source) }
                .map { ($0.source, $0.destination) }
        )

        if !successfulDestinationsBySource.isEmpty, var session {
            let lastOpenedSourceURL = session.lastOpenedItemID.flatMap { lastOpenedItemID in
                session.items.first(where: { $0.id == lastOpenedItemID })?.url
            }
            let updatedItems = session.items.map { item in
                guard let destination = successfulDestinationsBySource[item.url] else {
                    return item
                }

                return ImageItem(
                    url: destination,
                    format: SupportedImageFormat(fileExtension: destination.pathExtension) ?? item.format
                )
            }
            session.replaceItems(updatedItems)
            if let lastOpenedSourceURL,
               let destination = successfulDestinationsBySource[lastOpenedSourceURL],
               let renamedItem = updatedItems.first(where: {
                   $0.url.standardizedFileURL == destination.standardizedFileURL
               }) {
                session.recordOpenedItem(with: renamedItem.id)
            }
            session.selectedItemIDs = result.failures.map(\.url) + successfulDestinationsBySource.values.map { $0 }
            self.session = session
            onItemURLMutation?(.renamed(successfulDestinationsBySource))
        } else {
            session?.selectedItemIDs = result.failures.map(\.url)
        }

        operationMessage = message(for: result)
    }
}

private final class OpenFolderRequestTracker: @unchecked Sendable {
    private let lock = NSLock()
    private var generation: UInt64 = 0

    func next() -> UInt64 {
        lock.lock()
        defer { lock.unlock() }
        generation &+= 1
        return generation
    }

    func invalidate() {
        lock.lock()
        generation &+= 1
        lock.unlock()
    }

    func isCurrent(_ requestID: UInt64) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return generation == requestID
    }
}

private struct BatchRenameOperation: Sendable {
    let plan: BatchRenamePlan
    let result: BatchOperationResult
}
