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

struct FolderBatchProgress: Equatable {
    let processed: Int
    let total: Int
    let phase: String
    let isCancelling: Bool
}

private final class BatchCancellationToken: @unchecked Sendable {
    private let lock = NSLock()
    private var cancelled = false
    func cancel() { lock.withLock { cancelled = true } }
    var isCancelled: Bool { lock.withLock { cancelled } }
}

private final class WeakFolderBrowserViewModelBox: @unchecked Sendable {
    weak var value: FolderBrowserViewModel?
    init(_ value: FolderBrowserViewModel) { self.value = value }
}

@MainActor
final class FolderBrowserViewModel: ObservableObject {
    typealias ScanFolder = @Sendable (URL) async throws -> [ImageItem]
    typealias MoveToTrash = @Sendable ([URL]) -> BatchOperationResult
    typealias MoveToFolder = @Sendable ([URL], URL, MoveConflictPolicy) -> BatchOperationResult
    typealias PlanBatchMove = @Sendable ([URL], URL, MoveConflictPolicy) -> BatchMovePlan
    typealias ExecuteMovePlan = @Sendable (BatchMovePlan) -> BatchOperationResult
    typealias PlanBatchRename = @Sendable ([URL], String, Int, Int) -> BatchRenamePlan
    typealias ExecuteRenamePlan = @Sendable (BatchRenamePlan) -> BatchOperationResult

    @Published private(set) var session: FolderSession?
    @Published private(set) var selectedItemIDs: [ImageItem.ID] = []
    @Published private(set) var isLoading = false
    @Published private(set) var isOperating = false
    @Published private(set) var operationMessage: String?
    @Published private(set) var operationFailures: [BatchFileFailure] = []
    @Published private(set) var operationRecoveryFailures: [BatchRecoveryFailure] = []
    @Published private(set) var operationProgress: FolderBatchProgress?
    @Published private(set) var canUndoLastBatchOperation = false
    @Published private(set) var loadErrorMessage: String?
    private(set) var requestedFolderURL: URL?
    var onItemURLMutation: ((FolderItemURLMutation) -> Void)?
    var onRecoveryRequired: ((URL, [BatchRecoveryFailure]) -> Void)?

    var visibleItems: [ImageItem] {
        session?.visibleItems ?? []
    }

    var selectedItems: [ImageItem] {
        let selectedIDs = Set(selectedItemIDs)
        return visibleItems.filter { selectedIDs.contains($0.id) }
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
    private let planBatchMoveOperation: PlanBatchMove
    private let executeMovePlanOperation: ExecuteMovePlan
    private let planBatchRenameOperation: PlanBatchRename
    private let executeRenamePlanOperation: ExecuteRenamePlan
    private let usesDefaultMoveToTrash: Bool
    private let usesDefaultMoveToFolder: Bool
    private let usesDefaultExecuteMovePlan: Bool
    private let usesDefaultExecuteRenamePlan: Bool
    private var activeCancellationToken: BatchCancellationToken?
    private var lastBatchUndo: FolderBatchUndo?
    nonisolated private let openFolderRequestTracker = OpenFolderRequestTracker()
    private var sessionGeneration: UInt64 = 0
    var beforeOpenFolderCommitForTesting: (() -> Void)?

    init(
        scanFolder: @escaping ScanFolder = {
            try await DirectoryScanner().scan(folder: $0)
        },
        moveToTrash: MoveToTrash? = nil,
        moveToFolder: MoveToFolder? = nil,
        planBatchMove: PlanBatchMove? = nil,
        executeMovePlan: ExecuteMovePlan? = nil,
        planBatchRename: PlanBatchRename? = nil,
        executeRenamePlan: ExecuteRenamePlan? = nil
    ) {
        self.scanFolder = scanFolder
        self.usesDefaultMoveToTrash = moveToTrash == nil
        self.usesDefaultMoveToFolder = moveToFolder == nil
        self.usesDefaultExecuteMovePlan = executeMovePlan == nil
        self.usesDefaultExecuteRenamePlan = executeRenamePlan == nil
        self.moveToTrashOperation = moveToTrash ?? { BatchFileOperationService().moveToTrash($0) }
        self.moveToFolderOperation = moveToFolder ?? {
            BatchFileOperationService().moveToFolder($0, destinationFolder: $1, conflictPolicy: $2)
        }
        self.planBatchMoveOperation = planBatchMove ?? {
            BatchFileOperationService().planMoveToFolder($0, destinationFolder: $1, conflictPolicy: $2)
        }
        self.executeMovePlanOperation = executeMovePlan ?? {
            BatchFileOperationService().executeMovePlan($0)
        }
        self.planBatchRenameOperation = planBatchRename ?? {
            BatchFileOperationService().planBatchRename(urls: $0, baseName: $1, startNumber: $2, padding: $3)
        }
        self.executeRenamePlanOperation = executeRenamePlan ?? {
            BatchFileOperationService().executeRenamePlan($0)
        }
    }

    func openFolder(_ folderURL: URL) async {
        let requestID = openFolderRequestTracker.next()
        await withTaskCancellationHandler {
            guard !Task.isCancelled else {
                openFolderRequestTracker.invalidate(requestID)
                return
            }
            guard openFolderRequestTracker.withCurrent(requestID, perform: {
                sessionGeneration &+= 1
                requestedFolderURL = folderURL
                isLoading = true
                loadErrorMessage = nil
                operationMessage = nil
                operationFailures = []
                operationRecoveryFailures = []
                clearBatchUndo()
            }) else {
                return
            }

            do {
                let items = try await scanFolder(folderURL)
                guard !Task.isCancelled else {
                    openFolderRequestTracker.invalidate(requestID)
                    return
                }
                beforeOpenFolderCommitForTesting?()
                _ = openFolderRequestTracker.withCurrent(requestID, perform: {
                    session = FolderSession(folderURL: folderURL, items: items)
                    selectedItemIDs = []
                    loadErrorMessage = nil
                    isLoading = false
                })
            } catch is CancellationError {
                _ = openFolderRequestTracker.withCurrent(requestID, perform: {
                    isLoading = false
                    loadErrorMessage = nil
                })
            } catch {
                guard !Task.isCancelled else {
                    openFolderRequestTracker.invalidate(requestID)
                    return
                }
                beforeOpenFolderCommitForTesting?()
                _ = openFolderRequestTracker.withCurrent(requestID, perform: {
                    session = FolderSession(folderURL: folderURL, items: [])
                    selectedItemIDs = []
                    loadErrorMessage = String(
                        format: AppStrings.text("folderBrowser.error.openFolder"),
                        error.localizedDescription
                    )
                    isLoading = false
                })
            }
        } onCancel: {
            openFolderRequestTracker.invalidate(requestID)
        }
    }

    nonisolated func invalidateOpenFolderRequest() {
        openFolderRequestTracker.invalidate()
    }

    func cancelOpenFolderRequest() {
        invalidateOpenFolderRequest()
        sessionGeneration &+= 1
        requestedFolderURL = nil
        isLoading = false
        loadErrorMessage = nil
    }

    func cancelCurrentOperation() {
        guard let activeCancellationToken, let progress = operationProgress else { return }
        activeCancellationToken.cancel()
        operationProgress = FolderBatchProgress(
            processed: progress.processed,
            total: progress.total,
            phase: progress.phase,
            isCancelling: true
        )
    }

    @discardableResult
    func undoLastBatchOperation() -> Task<Void, Never>? {
        guard !isOperating, let undo = lastBatchUndo else { return nil }
        clearBatchUndo()

        switch undo {
        case .move(let proposals):
            let reverseProposals = proposals.map {
                BatchMoveProposal(source: $0.destination, destination: $0.source)
            }
            let reversePlan = BatchMovePlan(proposals: reverseProposals, failures: [])
            let operation = executeMovePlanOperation
            return runBatchOperation {
                operation(reversePlan)
            } apply: { [weak self] result in
                self?.applyMoveUndoResult(result, reversePlan: reversePlan)
            }
        case .rename(let proposals):
            let reversePlan = BatchRenamePlan(
                proposals: proposals.map {
                    RenameProposal(source: $0.destination, destination: $0.source)
                },
                failures: []
            )
            let operation = executeRenamePlanOperation
            return runBatchOperation {
                operation(reversePlan)
            } apply: { [weak self] result in
                guard let self else { return }
                self.publishRenameMutation(for: result, plan: reversePlan)
                self.applyRenameResult(result, plan: reversePlan)
            }
        }
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
        guard session != nil else { return }
        var seenIDs: Set<ImageItem.ID> = []
        let orderedIDs = selectedItemIDs.filter { id in
            seenIDs.insert(id).inserted
        }
        guard self.selectedItemIDs != orderedIDs else { return }
        self.selectedItemIDs = orderedIDs
    }

    func recordOpenedItem(_ item: ImageItem) {
        session?.recordOpenedItem(with: item.id)
    }

    func setSortMode(_ sortMode: FolderSortMode) {
        session?.sortMode = sortMode
    }

    func setFilter(_ filter: FolderFilter) {
        session?.filter = filter
        reconcileSelection()
    }

    func setAllowedFormats(_ allowedFormats: Set<SupportedImageFormat>) {
        updateFilter { $0.allowedFormats = allowedFormats }
    }

    func applyOperationResult(_ result: BatchOperationResult, removingSucceeded: Bool) {
        operationFailures = result.failures
        operationRecoveryFailures = result.recoveryFailures

        if removingSucceeded {
            let succeededIDs = Set(result.succeeded)
            session?.removeItems(with: succeededIDs)
            if !succeededIDs.isEmpty {
                onItemURLMutation?(.removed(succeededIDs))
            }
        }

        let failedIDs = result.failures.map(\.url)
        setSelection(failedIDs)
        operationMessage = message(for: result)
    }

    @discardableResult
    func moveSelectedToTrash() -> Task<Void, Never>? {
        guard !isOperating else { return nil }
        let urls = selectedItems.map(\.url)
        guard !urls.isEmpty else { return nil }
        if usesDefaultMoveToTrash {
            return runProgressiveBatchOperation(
                total: urls.count,
                phase: AppStrings.text("folderBrowser.progress.trash")
            ) { token, report in
                BatchFileOperationService().moveToTrash(
                    urls,
                    shouldCancel: { token.isCancelled },
                    progress: report
                )
            } apply: { [weak self] result in
                self?.applyOperationResult(result, removingSucceeded: true)
            }
        }
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
        if usesDefaultMoveToFolder {
            return runProgressiveBatchOperation(
                total: urls.count,
                phase: AppStrings.text("folderBrowser.progress.move")
            ) { token, report in
                BatchFileOperationService().moveToFolder(
                    urls,
                    destinationFolder: destinationFolder,
                    conflictPolicy: conflictPolicy,
                    shouldCancel: { token.isCancelled },
                    progress: report
                )
            } apply: { [weak self] result in
                self?.applyOperationResult(result, removingSucceeded: true)
            }
        }
        let operation = moveToFolderOperation
        return runBatchOperation {
            operation(urls, destinationFolder, conflictPolicy)
        } apply: { [weak self] result in
            self?.applyOperationResult(result, removingSucceeded: true)
        }
    }

    func planSelectedMove(to destinationFolder: URL, conflictPolicy: MoveConflictPolicy) -> BatchMovePlan? {
        guard !isOperating else { return nil }
        let urls = selectedItems.map(\.url)
        guard !urls.isEmpty else { return nil }
        return planBatchMoveOperation(urls, destinationFolder, conflictPolicy)
    }

    @discardableResult
    func executeMovePlan(_ plan: BatchMovePlan) -> Task<Void, Never>? {
        guard !isOperating else { return nil }
        if usesDefaultExecuteMovePlan {
            return runProgressiveBatchOperation(
                total: plan.proposals.count + plan.failures.count,
                phase: AppStrings.text("folderBrowser.progress.move")
            ) { token, report in
                BatchFileOperationService().executeMovePlan(
                    plan,
                    shouldCancel: { token.isCancelled },
                    progress: report
                )
            } apply: { [weak self] result in
                self?.applyOperationResult(result, removingSucceeded: true)
                self?.recordMoveUndoIfSafe(result: result, plan: plan)
            }
        }
        let operation = executeMovePlanOperation
        return runBatchOperation {
            operation(plan)
        } apply: { [weak self] result in
            self?.applyOperationResult(result, removingSucceeded: true)
            self?.recordMoveUndoIfSafe(result: result, plan: plan)
        }
    }

    @discardableResult
    func renameSelected(baseName: String, startNumber: Int = 1, padding: Int = 2) -> Task<Void, Never>? {
        guard !isOperating else { return nil }
        let urls = selectedItems.map(\.url)
        guard !urls.isEmpty else { return nil }
        let plan = planBatchRename(
            urls: urls,
            baseName: baseName,
            startNumber: startNumber,
            padding: padding
        )
        guard plan.isExecutable else {
            let operationSessionGeneration = sessionGeneration
            return runBatchOperation {
                BatchRenameOperation(
                    plan: plan,
                    result: BatchOperationResult(failures: plan.failures),
                    rescanOutcome: .notRequired
                )
            } apply: { [weak self] operation in
                guard self?.sessionGeneration == operationSessionGeneration else { return }
                self?.applyRenameResult(operation.result, plan: operation.plan)
            }
        }
        return executeRenamePlan(plan)
    }

    func planBatchRename(
        urls: [URL],
        baseName: String,
        startNumber: Int,
        padding: Int
    ) -> BatchRenamePlan {
        planBatchRenameOperation(urls, baseName, startNumber, padding)
    }

    @discardableResult
    func executeRenamePlan(_ plan: BatchRenamePlan) -> Task<Void, Never>? {
        guard !isOperating,
              plan.isExecutable,
              let activeFolderURL = session?.folderURL else { return nil }
        let executeOperation = executeRenamePlanOperation
        let scanFolder = scanFolder
        let operationSessionGeneration = sessionGeneration
        if usesDefaultExecuteRenamePlan {
            return runProgressiveBatchOperation(
                total: plan.proposals.count * 2,
                phase: AppStrings.text("folderBrowser.progress.rename")
            ) { token, report in
                let result = BatchFileOperationService().executeRenamePlan(
                    plan,
                    shouldCancel: { token.isCancelled },
                    progress: report
                )
                let needsRescan = !result.failures.isEmpty || !result.recoveryFailures.isEmpty
                let rescanOutcome: RenameRescanOutcome
                if needsRescan {
                    do {
                        let items = try await scanFolder(activeFolderURL)
                        rescanOutcome = .success(folderURL: activeFolderURL, items: items)
                    } catch {
                        rescanOutcome = .failure(folderURL: activeFolderURL, reason: error.localizedDescription)
                    }
                } else {
                    rescanOutcome = .notRequired
                }
                return BatchRenameOperation(plan: plan, result: result, rescanOutcome: rescanOutcome)
            } apply: { [weak self] operation in
                guard let self else { return }
                self.publishRenameMutation(for: operation.result, plan: operation.plan)
                guard self.sessionGeneration == operationSessionGeneration,
                      self.session?.folderURL == activeFolderURL else {
                    if !operation.result.recoveryFailures.isEmpty {
                        self.onRecoveryRequired?(activeFolderURL, operation.result.recoveryFailures)
                    }
                    return
                }
                self.applyRenameResult(
                    operation.result,
                    plan: operation.plan,
                    rescanOutcome: operation.rescanOutcome
                )
                self.recordRenameUndoIfSafe(result: operation.result, plan: operation.plan)
            }
        }
        return runBatchOperation {
            let result = executeOperation(plan)
            let needsRescan = !result.failures.isEmpty || !result.recoveryFailures.isEmpty
            let rescanOutcome: RenameRescanOutcome
            if needsRescan {
                do {
                    let items = try await scanFolder(activeFolderURL)
                    rescanOutcome = .success(folderURL: activeFolderURL, items: items)
                } catch {
                    rescanOutcome = .failure(
                        folderURL: activeFolderURL,
                        reason: error.localizedDescription
                    )
                }
            } else {
                rescanOutcome = .notRequired
            }
            return BatchRenameOperation(plan: plan, result: result, rescanOutcome: rescanOutcome)
        } apply: { [weak self] (operation: BatchRenameOperation) in
            guard let self else { return }
            self.publishRenameMutation(for: operation.result, plan: operation.plan)
            guard self.sessionGeneration == operationSessionGeneration,
                  self.session?.folderURL == activeFolderURL else {
                if !operation.result.recoveryFailures.isEmpty {
                    self.onRecoveryRequired?(activeFolderURL, operation.result.recoveryFailures)
                }
                return
            }
            self.applyRenameResult(
                operation.result,
                plan: operation.plan,
                rescanOutcome: operation.rescanOutcome
            )
            self.recordRenameUndoIfSafe(result: operation.result, plan: operation.plan)
        }
    }

    private func runBatchOperation<Value: Sendable>(
        _ operation: @escaping @Sendable () async -> Value,
        apply: @escaping @MainActor (Value) -> Void
    ) -> Task<Void, Never> {
        clearBatchUndo()
        isOperating = true
        operationProgress = nil
        operationFailures = []
        operationRecoveryFailures = []
        operationMessage = nil

        return Task { [weak self] in
            let value = await Task.detached(priority: .userInitiated) {
                await operation()
            }.value
            guard let self else { return }
            apply(value)
            self.isOperating = false
        }
    }

    private func runProgressiveBatchOperation<Value: Sendable>(
        total: Int,
        phase: String,
        _ operation: @escaping @Sendable (
            BatchCancellationToken,
            @escaping @Sendable (Int, Int) -> Void
        ) async -> Value,
        apply: @escaping @MainActor (Value) -> Void
    ) -> Task<Void, Never> {
        clearBatchUndo()
        isOperating = true
        operationFailures = []
        operationRecoveryFailures = []
        operationMessage = nil
        let token = BatchCancellationToken()
        activeCancellationToken = token
        operationProgress = FolderBatchProgress(processed: 0, total: total, phase: phase, isCancelling: false)
        let owner = WeakFolderBrowserViewModelBox(self)

        return Task { [weak self] in
            let value = await Task.detached(priority: .userInitiated) {
                await operation(token) { processed, reportedTotal in
                    Task { @MainActor in
                        guard let self = owner.value, self.activeCancellationToken === token else { return }
                        self.operationProgress = FolderBatchProgress(
                            processed: processed,
                            total: reportedTotal,
                            phase: phase,
                            isCancelling: token.isCancelled
                        )
                    }
                }
            }.value
            guard let self, self.activeCancellationToken === token else { return }
            apply(value)
            self.activeCancellationToken = nil
            self.operationProgress = nil
            self.isOperating = false
        }
    }

    private func updateFilter(_ update: (inout FolderFilter) -> Void) {
        guard var filter = session?.filter else {
            return
        }
        update(&filter)
        session?.filter = filter
        reconcileSelection()
    }

    private func reconcileSelection() {
        setSelection(selectedItemIDs)
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

    private func clearBatchUndo() {
        lastBatchUndo = nil
        canUndoLastBatchOperation = false
    }

    private func recordMoveUndoIfSafe(result: BatchOperationResult, plan: BatchMovePlan) {
        guard result.failures.isEmpty,
              result.recoveryFailures.isEmpty,
              !plan.proposals.isEmpty,
              Set(result.succeeded) == Set(plan.proposals.map(\.source)) else { return }
        if usesDefaultExecuteMovePlan {
            guard plan.proposals.allSatisfy({
                FileManager.default.fileExists(atPath: $0.destination.path)
                    && !FileManager.default.fileExists(atPath: $0.source.path)
            }) else { return }
        }
        lastBatchUndo = .move(plan.proposals)
        canUndoLastBatchOperation = true
    }

    private func recordRenameUndoIfSafe(result: BatchOperationResult, plan: BatchRenamePlan) {
        let activeProposals = plan.proposals.filter {
            $0.source.standardizedFileURL != $0.destination.standardizedFileURL
        }
        guard result.failures.isEmpty,
              result.recoveryFailures.isEmpty,
              !activeProposals.isEmpty,
              Set(result.succeeded) == Set(plan.proposals.map(\.source)) else { return }
        if usesDefaultExecuteRenamePlan {
            guard activeProposals.allSatisfy({
                FileManager.default.fileExists(atPath: $0.destination.path)
                    && !FileManager.default.fileExists(atPath: $0.source.path)
            }) else { return }
        }
        lastBatchUndo = .rename(activeProposals)
        canUndoLastBatchOperation = true
    }

    private func applyMoveUndoResult(_ result: BatchOperationResult, reversePlan: BatchMovePlan) {
        operationFailures = result.failures
        operationRecoveryFailures = result.recoveryFailures
        let succeededSources = Set(result.succeeded)
        let restoredURLs = reversePlan.proposals
            .filter { succeededSources.contains($0.source) }
            .map(\.destination)

        if var session, !restoredURLs.isEmpty {
            let existingURLs = Set(session.items.map { $0.url.standardizedFileURL })
            let restoredItems = restoredURLs.compactMap { url -> ImageItem? in
                guard !existingURLs.contains(url.standardizedFileURL),
                      let format = SupportedImageFormat(fileExtension: url.pathExtension) else { return nil }
                return ImageItem(url: url, format: format)
            }
            session.replaceItems(session.items + restoredItems)
            self.session = session
            setSelection(restoredURLs)
        }
        operationMessage = message(for: result)
    }

    private func applyRenameResult(
        _ result: BatchOperationResult,
        plan: BatchRenamePlan,
        rescanOutcome: RenameRescanOutcome = .notRequired
    ) {
        operationFailures = result.failures
        operationRecoveryFailures = result.recoveryFailures

        if !result.failures.isEmpty || !result.recoveryFailures.isEmpty {
            switch rescanOutcome {
            case .notRequired:
                setSelection(result.failures.map(\.url))
            case .success(let folderURL, let items):
                guard session?.folderURL == folderURL else { return }
                session?.replaceItems(items)
                let candidateURLs = Set(
                    result.failures.map(\.url) +
                    result.recoveryFailures.flatMap { [$0.expectedURL, $0.actualURL] }
                )
                setSelection(session?.visibleItems
                    .map(\.url)
                    .filter(candidateURLs.contains) ?? [])
                loadErrorMessage = nil
            case .failure(let folderURL, let reason):
                if session?.folderURL == folderURL {
                    session?.replaceItems([])
                } else {
                    session = FolderSession(folderURL: folderURL, items: [])
                }
                requestedFolderURL = folderURL
                loadErrorMessage = String(
                    format: AppStrings.text("folderBrowser.error.openFolder"),
                    reason
                )
            }
            operationMessage = message(for: result)
            return
        }

        let successfulDestinationsBySource = successfulRenameMigrations(for: result, plan: plan)

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
            self.session = session
            setSelection(result.failures.map(\.url) + successfulDestinationsBySource.values.map { $0 })
        } else {
            setSelection(result.failures.map(\.url))
        }

        operationMessage = message(for: result)
    }

    private func publishRenameMutation(for result: BatchOperationResult, plan: BatchRenamePlan) {
        let migrations = successfulRenameMigrations(for: result, plan: plan)
        guard !migrations.isEmpty else { return }
        onItemURLMutation?(.renamed(migrations))
    }

    private func successfulRenameMigrations(
        for result: BatchOperationResult,
        plan: BatchRenamePlan
    ) -> [URL: URL] {
        let succeededSources = Set(result.succeeded)
        return Dictionary(
            uniqueKeysWithValues: plan.proposals
                .filter { succeededSources.contains($0.source) }
                .map { ($0.source, $0.destination) }
        )
    }
}

private final class OpenFolderRequestTracker: @unchecked Sendable {
    private let lock = NSRecursiveLock()
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

    func invalidate(_ requestID: UInt64) {
        lock.lock()
        if generation == requestID {
            generation &+= 1
        }
        lock.unlock()
    }

    func withCurrent(_ requestID: UInt64, perform commit: () -> Void) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard generation == requestID else { return false }
        commit()
        return true
    }
}

private struct BatchRenameOperation: Sendable {
    let plan: BatchRenamePlan
    let result: BatchOperationResult
    let rescanOutcome: RenameRescanOutcome
}

private enum RenameRescanOutcome: Sendable {
    case notRequired
    case success(folderURL: URL, items: [ImageItem])
    case failure(folderURL: URL, reason: String)
}

private enum FolderBatchUndo {
    case move([BatchMoveProposal])
    case rename([RenameProposal])
}
