# Folder Browser Batch Safety Corrections Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make Move to Folder and Batch Rename conservative before execution, collision-safe during execution, and recoverable after a file-system failure.

**Architecture:** Keep file-system decisions in `BatchFileOperationService` and expose immutable move/rename plans to the App layer. The controller renders conflicts and passes an explicit safe policy; the rename sheet renders the same Core plan that will execute. Rename execution uses a journaled two-phase transaction with deterministic file-system fault injection so every partial failure is rolled back or explicitly reported.

**Tech Stack:** Swift 6, AppKit, Swift Package Manager, XCTest, Foundation `FileManager`.

---

## File map

- `Sources/ImageViewCore/Files/BatchFileOperationService.swift`: move preflight plans, keep-both reservation, rename transaction journal and rollback reporting.
- `Sources/ImageViewApp/FolderBrowser/FolderBrowserViewModel.swift`: injectable plan/execute boundaries and mutation/result application.
- `Sources/ImageViewApp/FolderBrowser/BatchRenameSheetController.swift`: real Core-plan preview, conflict validation, computed default padding.
- `Sources/ImageViewApp/MainWindowController.swift`: move-conflict choice sheet and plan wiring.
- `Sources/ImageViewApp/Localization/AppStrings.swift` and localization resources: conflict and recovery copy.
- `Tests/ImageViewCoreTests/BatchFileOperationServiceTests.swift`: move reservation and rename rollback fault matrix.
- `Tests/ImageViewAppTests/BatchRenameSheetControllerTests.swift`: real-plan preview/validation.
- `Tests/ImageViewAppTests/MainWindowControllerTests.swift`: conflict choice and cancel wiring.
- `Tests/ImageViewAppTests/FolderBrowserViewModelTests.swift`: only real successes mutate the session.

### Task 1: Add immutable Move plans and deterministic Keep Both names

**Files:**
- Modify: `Sources/ImageViewCore/Files/BatchFileOperationService.swift`
- Test: `Tests/ImageViewCoreTests/BatchFileOperationServiceTests.swift`

- [ ] **Step 1: Write failing Core tests**

Add tests proving: preflight returns every existing destination conflict before mutation; `.skip` excludes conflicting proposals; `.keepBoth` reserves unique names across both disk contents and earlier proposals; execution never overwrites a destination.

```swift
func testPlanMoveKeepBothReservesNamesAcrossBatch() throws {
    let sourceA = try fixture.makeSource("photo.png")
    let sourceB = try fixture.makeSource("nested/photo.png")
    try fixture.makeDestination("photo.png")
    try fixture.makeDestination("photo copy.png")

    let plan = service.planMoveToFolder(
        [sourceA, sourceB],
        destinationFolder: fixture.destination,
        conflictPolicy: .keepBoth
    )

    XCTAssertEqual(plan.proposals.map(\.destination.lastPathComponent), [
        "photo copy 2.png", "photo copy 3.png"
    ])
    XCTAssertTrue(plan.failures.isEmpty)
}
```

- [ ] **Step 2: Run the focused tests and verify RED**

Run: `swift test --disable-sandbox --filter BatchFileOperationServiceTests`

Expected: compile failure because `BatchMovePlan` and `planMoveToFolder` do not exist.

- [ ] **Step 3: Add the Move plan types and planner**

```swift
public struct BatchMoveProposal: Equatable, Sendable {
    public let source: URL
    public let destination: URL
}

public struct BatchMovePlan: Equatable, Sendable {
    public let proposals: [BatchMoveProposal]
    public let failures: [BatchFileFailure]
    public var conflictingNames: [String] {
        failures.compactMap { $0.reason == .destinationExists ? $0.url.lastPathComponent : nil }
    }
}
```

Implement `planMoveToFolder` with a normalized reserved-path set initialized from destination directory contents. For `.skip`, append `.destinationExists`; for `.keepBoth`, choose `name copy.ext`, then `name copy 2.ext`, incrementing until both disk and reserved sets are free. Make `moveToFolder` a compatibility wrapper around plan plus execution.

- [ ] **Step 4: Run Core tests and verify GREEN**

Run: `swift test --disable-sandbox --filter BatchFileOperationServiceTests`

Expected: all focused tests pass and source files remain untouched during planning.

- [ ] **Step 5: Commit Task 1**

```bash
git add Sources/ImageViewCore/Files/BatchFileOperationService.swift Tests/ImageViewCoreTests/BatchFileOperationServiceTests.swift
git commit -m "feat: preflight batch move conflicts"
```

### Task 2: Show all Move conflicts and require a safe user choice

**Files:**
- Modify: `Sources/ImageViewApp/FolderBrowser/FolderBrowserViewModel.swift`
- Modify: `Sources/ImageViewApp/MainWindowController.swift`
- Modify: localization files discovered by `rg -n 'folderBrowser.move' Sources/ImageViewApp`
- Test: `Tests/ImageViewAppTests/MainWindowControllerTests.swift`
- Test: `Tests/ImageViewAppTests/FolderBrowserViewModelTests.swift`

- [ ] **Step 1: Write failing controller and ViewModel tests**

```swift
func testMoveConflictsRequireSkipKeepBothOrCancelBeforeExecution() async {
    for choice in [MoveConflictChoice.cancel, .skipConflicts, .keepBoth] {
        let executedPolicies = LockedValue<[MoveConflictPolicy]>([])
        let fixture = makeMoveConflictFixture(
            conflicts: ["a.png", "b.png"],
            onExecute: { policy in executedPolicies.update { $0.append(policy) } }
        )
        fixture.controller.batchActionDialogProviderForTesting = .init(
            chooseDestinationFolder: { fixture.destination },
            chooseMoveConflict: { names in
                XCTAssertEqual(names, ["a.png", "b.png"])
                return choice
            }
        )

        fixture.controller.triggerFolderBrowserMoveForTesting()
        await fixture.waitForOperationToFinish()

        let expected: [MoveConflictPolicy]
        switch choice {
        case .cancel: expected = []
        case .skipConflicts: expected = [.skip]
        case .keepBoth: expected = [.keepBoth]
        }
        XCTAssertEqual(executedPolicies.value, expected)
    }
}
```

Also assert session removal uses only `result.succeeded`, never planned proposals or conflicts.

- [ ] **Step 2: Run focused App tests and verify RED**

Run: `swift test --disable-sandbox --filter 'MainWindowControllerTests|FolderBrowserViewModelTests'`

Expected: compile failure for the new conflict-choice provider and move-plan injection points.

- [ ] **Step 3: Add planning and conflict choice wiring**

Add `PlanBatchMove` and `ExecuteMovePlan` closures to `FolderBrowserViewModel`. In `MainWindowController`, preflight with `.skip` after choosing a folder. If there are conflicts, show one alert listing every conflicting filename in a scrollable accessory view and map buttons to:

```swift
enum MoveConflictChoice { case skipConflicts, keepBoth, cancel }
```

Cancel performs no mutation. Skip executes the skip plan. Keep Both replans with `.keepBoth` immediately before execution and executes that plan. Do not offer overwrite.

- [ ] **Step 4: Run focused tests and verify GREEN**

Run: `swift test --disable-sandbox --filter 'MainWindowControllerTests|FolderBrowserViewModelTests'`

Expected: all focused tests pass, including cancel/no-write and complete conflict-name delivery.

- [ ] **Step 5: Commit Task 2**

```bash
git add Sources/ImageViewApp Tests/ImageViewAppTests
git commit -m "feat: add safe move conflict choices"
```

### Task 3: Drive Batch Rename preview and validation from the executable Core plan

**Files:**
- Modify: `Sources/ImageViewApp/FolderBrowser/BatchRenameSheetController.swift`
- Modify: `Sources/ImageViewApp/MainWindowController.swift`
- Modify: `Sources/ImageViewApp/FolderBrowser/FolderBrowserViewModel.swift`
- Test: `Tests/ImageViewAppTests/BatchRenameSheetControllerTests.swift`
- Test: `Tests/ImageViewAppTests/MainWindowControllerTests.swift`

- [ ] **Step 1: Write failing sheet tests**

Add tests that inject a planner returning `.duplicateDestination` and `.destinationExists`, assert the exact conflicting old/new rows are visible, and assert confirm is not called. Add count-based padding cases: 1 item -> 1 digit, 10 and 42 items -> 2 digits, 100 items -> 3 digits.

- [ ] **Step 2: Run the sheet tests and verify RED**

Run: `swift test --disable-sandbox --filter BatchRenameSheetControllerTests`

Expected: failures because the sheet currently builds preview strings independently and defaults padding to `2`.

- [ ] **Step 3: Inject the Core planner into the sheet**

```swift
typealias PlanRename = ([URL], String, Int, Int) -> BatchRenamePlan

init(items: [ImageItem], planRename: @escaping PlanRename) {
    self.items = items
    self.planRename = planRename
    self.defaultPadding = max(1, String(items.count).count)
}
```

Every input change computes one `BatchRenamePlan`; preview rows come from `plan.proposals`; validation messages come from all `plan.failures`; the Rename button is enabled only when `plan.isExecutable`. On confirm, pass both validated parameters and that exact plan so execution cannot diverge from preview.

- [ ] **Step 4: Run sheet/controller tests and verify GREEN**

Run: `swift test --disable-sandbox --filter 'BatchRenameSheetControllerTests|MainWindowControllerTests'`

Expected: all tests pass; real destination conflicts keep the sheet open and disable Rename.

- [ ] **Step 5: Commit Task 3**

```bash
git add Sources/ImageViewApp Tests/ImageViewAppTests
git commit -m "fix: validate batch rename preview with core plan"
```

### Task 4: Make two-phase Rename rollback explicit and fault-testable

**Files:**
- Modify: `Sources/ImageViewCore/Files/BatchFileOperationService.swift`
- Test: `Tests/ImageViewCoreTests/BatchFileOperationServiceTests.swift`
- Modify: `Sources/ImageViewApp/FolderBrowser/FolderBrowserViewModel.swift`
- Test: `Tests/ImageViewAppTests/FolderBrowserViewModelTests.swift`

- [ ] **Step 1: Write failing second-phase and rollback-failure tests**

Create a test-only `FaultInjectingBatchFileSystem` that fails on a chosen `moveItem` call. Cover: phase-one failure restores every original; phase-two failure first rolls committed destinations back to their temporary URLs, then restores all temporaries to originals; rollback failure is returned in `recoveryFailures`; no `.batch-rename-*.tmp` remains when recovery succeeds.

- [ ] **Step 2: Run Core tests and verify RED**

Run: `swift test --disable-sandbox --filter BatchFileOperationServiceTests`

Expected: phase-two atomicity and recovery reporting tests fail against the current `try?` rollback.

- [ ] **Step 3: Add an injected file-system boundary and rename journal**

```swift
public protocol BatchFileSystem: Sendable {
    func fileExists(at url: URL) -> Bool
    func directoryContents(at url: URL) throws -> [URL]
    func moveItem(at source: URL, to destination: URL) throws
    func trashItem(at url: URL) throws
}

public struct BatchRecoveryFailure: Equatable, Sendable {
    public let expectedURL: URL
    public let actualURL: URL
    public let reason: String
}
```

Record journal states `.original`, `.temporary`, and `.destination`. On phase-two failure: reverse committed destination moves back to their recorded temporary URLs; then reverse every temporary to its original URL. Never swallow rollback errors. Return all primary failures plus `recoveryFailures` containing the best-known actual URL.

- [ ] **Step 4: Rescan after any Rename execution failure**

In `FolderBrowserViewModel`, if rename returns failures or recovery failures, call the existing folder scanner for the active folder before applying selection. Select still-existing failed/recovery URLs from the rescan; do not synthesize session state from proposals.

- [ ] **Step 5: Run focused and full verification**

Run:

```bash
swift test --disable-sandbox --filter 'BatchFileOperationServiceTests|FolderBrowserViewModelTests'
swift test --disable-sandbox
scripts/build-app.sh
/Users/zhupin/.codex/hooks/secret-scan.sh .
git diff --check
```

Expected: all tests pass, production app builds, secret scan and diff check return exit code 0.

- [ ] **Step 6: Commit Task 4**

```bash
git add Sources/ImageViewCore/Files/BatchFileOperationService.swift Sources/ImageViewApp/FolderBrowser/FolderBrowserViewModel.swift Tests/ImageViewCoreTests/BatchFileOperationServiceTests.swift Tests/ImageViewAppTests/FolderBrowserViewModelTests.swift
git commit -m "fix: make batch rename rollback recoverable"
```

### Task 5: Install and manual safety QA

**Files:**
- No source changes expected.

- [ ] **Step 1: Build and install**

Run: `scripts/install-app.sh`

Expected: `/Applications/ImageView.app` is replaced and ad-hoc signed.

- [ ] **Step 2: Verify with disposable fixtures only**

Create a temporary source and destination outside the repository. Verify: conflict dialog lists all names; Cancel changes nothing; Skip leaves conflicts in source; Keep Both produces unique names; rename conflict blocks confirm; a valid rename preview exactly matches disk results. Never use the user's real image folders for mutation QA.

- [ ] **Step 3: Final verification and push**

Run:

```bash
swift test --disable-sandbox
git status --short --branch
git push origin main
```

Expected: all tests pass and `main` matches `origin/main`.
