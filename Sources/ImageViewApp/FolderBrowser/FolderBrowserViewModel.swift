import Combine
import Foundation
import ImageViewCore

@MainActor
final class FolderBrowserViewModel: ObservableObject {
    typealias ScanFolder = @Sendable (URL) async throws -> [ImageItem]
    typealias MoveToTrash = ([URL]) -> BatchOperationResult
    typealias MoveToFolder = ([URL], URL, MoveConflictPolicy) -> BatchOperationResult
    typealias PlanBatchRename = ([URL], String, Int, Int) -> BatchRenamePlan
    typealias ExecuteRenamePlan = (BatchRenamePlan) -> BatchOperationResult

    @Published private(set) var session: FolderSession?
    @Published private(set) var isLoading = false
    @Published private(set) var operationMessage: String?
    @Published private(set) var operationFailures: [BatchFileFailure] = []

    var visibleItems: [ImageItem] {
        session?.visibleItems ?? []
    }

    var selectedItems: [ImageItem] {
        session?.selectedItems ?? []
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

    init(
        scanFolder: @escaping ScanFolder = {
            try await DirectoryScanner().scan(folder: $0)
        },
        moveToTrash: MoveToTrash? = nil,
        moveToFolder: MoveToFolder? = nil,
        planBatchRename: PlanBatchRename? = nil,
        executeRenamePlan: ExecuteRenamePlan? = nil
    ) {
        let operationService = BatchFileOperationService()
        self.scanFolder = scanFolder
        self.moveToTrashOperation = moveToTrash ?? { operationService.moveToTrash($0) }
        self.moveToFolderOperation = moveToFolder ?? {
            operationService.moveToFolder($0, destinationFolder: $1, conflictPolicy: $2)
        }
        self.planBatchRenameOperation = planBatchRename ?? {
            operationService.planBatchRename(urls: $0, baseName: $1, startNumber: $2, padding: $3)
        }
        self.executeRenamePlanOperation = executeRenamePlan ?? {
            operationService.executeRenamePlan($0)
        }
    }

    func openFolder(_ folderURL: URL) async {
        isLoading = true
        operationMessage = nil
        operationFailures = []

        do {
            let items = try await scanFolder(folderURL)
            session = FolderSession(folderURL: folderURL, items: items)
        } catch {
            session = FolderSession(folderURL: folderURL, items: [])
            operationMessage = "Failed to open folder: \(error.localizedDescription)"
        }

        isLoading = false
    }

    func setSelection(_ selectedItemIDs: [ImageItem.ID]) {
        session?.selectedItemIDs = selectedItemIDs
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
        }

        let failedIDs = result.failures.map(\.url)
        session?.selectedItemIDs = failedIDs
        operationMessage = message(for: result)
    }

    func moveSelectedToTrash() {
        let result = moveToTrashOperation(selectedItems.map(\.url))
        applyOperationResult(result, removingSucceeded: true)
    }

    func moveSelected(to destinationFolder: URL, conflictPolicy: MoveConflictPolicy) {
        let result = moveToFolderOperation(selectedItems.map(\.url), destinationFolder, conflictPolicy)
        applyOperationResult(result, removingSucceeded: true)
    }

    func renameSelected(baseName: String, startNumber: Int = 1, padding: Int = 2) {
        let plan = planBatchRenameOperation(selectedItems.map(\.url), baseName, startNumber, padding)
        let result = plan.isExecutable ? executeRenamePlanOperation(plan) : BatchOperationResult(failures: plan.failures)
        applyOperationResult(result, removingSucceeded: false)
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
            return "\(result.succeeded.count) succeeded"
        case (0, _):
            return "\(result.failures.count) failed"
        default:
            return "\(result.succeeded.count) succeeded, \(result.failures.count) failed"
        }
    }
}
