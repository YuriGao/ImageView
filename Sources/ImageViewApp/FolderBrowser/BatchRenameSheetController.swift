import AppKit
import ImageViewCore

@MainActor
final class BatchRenameSheetController: NSWindowController, NSTextFieldDelegate {
    typealias PlanRename = ([URL], String, Int, Int) -> BatchRenamePlan

    struct RenameParameters: Equatable {
        let baseName: String
        let startNumber: Int
        let padding: Int
    }

    struct PreviewRow: Equatable {
        let oldName: String
        let newName: String
    }

    var onConfirm: ((RenameParameters, BatchRenamePlan) -> Void)?

    private let items: [ImageItem]
    private let planRename: PlanRename
    private let baseNameField = NSTextField(string: AppStrings.text("batchRename.defaultBaseName"))
    private let startNumberField = NSTextField(string: "1")
    private let paddingField: NSTextField
    private let previewStack = NSStackView()
    private let contentStack = NSStackView()
    private let errorLabel = NSTextField(labelWithString: "")
    private let renameButton = NSButton(title: AppStrings.text("batchRename.button.rename"), target: nil, action: nil)
    private var validatedParameters: RenameParameters?
    private var validatedPlan = BatchRenamePlan(proposals: [], failures: [])
    private var backgroundClickMonitor: Any?

    var previewRowsForTesting: [PreviewRow] {
        previewRows()
    }
    var validationErrorForTesting: String? {
        errorLabel.isHidden ? nil : errorLabel.stringValue
    }
    var renameButtonEnabledForTesting: Bool {
        renameButton.isEnabled
    }

    init(items: [ImageItem], planRename: @escaping PlanRename) {
        self.items = items
        self.planRename = planRename
        self.paddingField = NSTextField(string: "\(max(1, String(items.count).count))")
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 480, height: 360),
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )
        window.title = AppStrings.text("batchRename.title")
        super.init(window: window)
        buildView()
        updatePreview()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
    }

    func setBatchRenameInputsForTesting(baseName: String, startNumber: Int, padding: Int) {
        baseNameField.stringValue = baseName
        startNumberField.integerValue = startNumber
        paddingField.integerValue = padding
        updatePreview()
    }

    func confirmForTesting() {
        confirm(nil)
    }

    func beginSheet(on parentWindow: NSWindow, completionHandler: ((NSApplication.ModalResponse) -> Void)? = nil) {
        guard let sheet = window else { return }
        resizeToFitContent(maximumHeight: parentWindow.contentLayoutRect.height * 0.8)
        installBackgroundClickMonitor(for: parentWindow)
        parentWindow.beginSheet(sheet, completionHandler: completionHandler)
    }

    func dismissForBackgroundClickForTesting(in parentWindow: NSWindow) -> Bool {
        dismissForBackgroundClick(in: parentWindow)
    }

    private func buildView() {
        guard let window else { return }

        contentStack.orientation = .vertical
        contentStack.alignment = .leading
        contentStack.spacing = 12
        contentStack.translatesAutoresizingMaskIntoConstraints = false

        let title = NSTextField(labelWithString: AppStrings.text("batchRename.title"))
        title.font = .systemFont(ofSize: 18, weight: .semibold)

        let form = NSGridView(views: [
            [NSTextField(labelWithString: AppStrings.text("batchRename.field.baseName")), baseNameField],
            [NSTextField(labelWithString: AppStrings.text("batchRename.field.startNumber")), startNumberField],
            [NSTextField(labelWithString: AppStrings.text("batchRename.field.padding")), paddingField]
        ])
        form.rowSpacing = 8
        form.columnSpacing = 12
        form.translatesAutoresizingMaskIntoConstraints = false
        for field in [baseNameField, startNumberField, paddingField] {
            field.delegate = self
        }

        let previewTitle = NSTextField(labelWithString: AppStrings.text("batchRename.preview"))
        previewTitle.font = .systemFont(ofSize: 13, weight: .semibold)

        previewStack.orientation = .vertical
        previewStack.alignment = .leading
        previewStack.spacing = 4
        previewStack.translatesAutoresizingMaskIntoConstraints = false

        let buttonStack = NSStackView()
        buttonStack.orientation = .horizontal
        buttonStack.alignment = .centerY
        buttonStack.spacing = 8
        let cancelButton = NSButton(title: AppStrings.text("batchRename.button.cancel"), target: self, action: #selector(cancel(_:)))
        renameButton.target = self
        renameButton.action = #selector(confirm(_:))
        renameButton.keyEquivalent = "\r"
        buttonStack.addArrangedSubview(cancelButton)
        buttonStack.addArrangedSubview(renameButton)

        errorLabel.textColor = .systemRed
        errorLabel.font = .systemFont(ofSize: 12, weight: .medium)
        errorLabel.isHidden = true

        contentStack.addArrangedSubview(title)
        contentStack.addArrangedSubview(form)
        contentStack.addArrangedSubview(errorLabel)
        contentStack.addArrangedSubview(previewTitle)
        contentStack.addArrangedSubview(previewStack)
        contentStack.addArrangedSubview(buttonStack)
        window.contentView = NSView()
        window.contentView?.addSubview(contentStack)

        NSLayoutConstraint.activate([
            contentStack.leadingAnchor.constraint(equalTo: window.contentView!.leadingAnchor, constant: 20),
            contentStack.trailingAnchor.constraint(equalTo: window.contentView!.trailingAnchor, constant: -20),
            contentStack.topAnchor.constraint(equalTo: window.contentView!.topAnchor, constant: 20),
            contentStack.bottomAnchor.constraint(equalTo: window.contentView!.bottomAnchor, constant: -20),
            baseNameField.widthAnchor.constraint(greaterThanOrEqualToConstant: 260),
            startNumberField.widthAnchor.constraint(equalToConstant: 80),
            paddingField.widthAnchor.constraint(equalToConstant: 80)
        ])
    }

    func controlTextDidChange(_ notification: Notification) {
        updatePreview()
    }

    @objc private func cancel(_ sender: Any?) {
        closeSheet()
    }

    @objc private func confirm(_ sender: Any?) {
        guard let validatedParameters, validatedPlan.isExecutable else { return }
        closeSheet()
        onConfirm?(validatedParameters, validatedPlan)
    }

    private func parameters() -> RenameParameters {
        RenameParameters(
            baseName: baseNameField.stringValue,
            startNumber: startNumberField.integerValue,
            padding: paddingField.integerValue
        )
    }

    private func validateParameters() -> ValidationResult {
        let parameters = parameters()
        let trimmedBaseName = parameters.baseName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedBaseName.isEmpty else {
            return .invalid(AppStrings.text("batchRename.validation.baseNameRequired"))
        }
        guard !trimmedBaseName.contains("/"), !trimmedBaseName.contains(":") else {
            return .invalid(AppStrings.text("batchRename.validation.baseNameInvalid"))
        }
        guard parameters.startNumber > 0, parameters.padding >= 0 else {
            return .invalid(AppStrings.text("batchRename.validation.numberInvalid"))
        }
        return .valid(RenameParameters(
            baseName: trimmedBaseName,
            startNumber: parameters.startNumber,
            padding: parameters.padding
        ))
    }

    private func previewRows() -> [PreviewRow] {
        validatedPlan.proposals.map { proposal in
            PreviewRow(
                oldName: proposal.source.lastPathComponent,
                newName: proposal.destination.lastPathComponent
            )
        }
    }

    private func updatePreview() {
        let validation = validateParameters()
        let plannedParameters: RenameParameters
        switch validation {
        case .valid(let parameters):
            plannedParameters = parameters
            validatedParameters = parameters
        case .invalid:
            let rawParameters = parameters()
            plannedParameters = RenameParameters(
                baseName: rawParameters.baseName.trimmingCharacters(in: .whitespacesAndNewlines),
                startNumber: rawParameters.startNumber,
                padding: rawParameters.padding
            )
            validatedParameters = nil
        }
        validatedPlan = planRename(
            items.map(\.url),
            plannedParameters.baseName,
            plannedParameters.startNumber,
            plannedParameters.padding
        )

        let localValidationMessage: String?
        switch validation {
        case .invalid(let message):
            localValidationMessage = message
        case .valid:
            localValidationMessage = nil
        }
        let validationMessage = combinedValidationMessage(
            local: localValidationMessage,
            plan: planFailureMessage(validatedPlan)
        )
        if let validationMessage {
            errorLabel.stringValue = validationMessage
            errorLabel.isHidden = false
        } else {
            errorLabel.stringValue = ""
            errorLabel.isHidden = true
        }
        renameButton.isEnabled = validatedParameters != nil && validatedPlan.isExecutable

        previewStack.arrangedSubviews.forEach {
            previewStack.removeArrangedSubview($0)
            $0.removeFromSuperview()
        }

        for row in previewRows().prefix(8) {
            previewStack.addArrangedSubview(NSTextField(labelWithString: "\(row.oldName) → \(row.newName)"))
        }
        resizeToFitContent()
    }

    private func planFailureMessage(_ plan: BatchRenamePlan) -> String? {
        guard !plan.failures.isEmpty else { return nil }
        let destinationsBySource = Dictionary(
            uniqueKeysWithValues: plan.proposals.map { ($0.source.standardizedFileURL, $0.destination) }
        )
        return plan.failures.map { failure in
            let source = failure.url.standardizedFileURL
            let names: String
            if let destination = destinationsBySource[source] {
                names = "\(failure.url.lastPathComponent) → \(destination.lastPathComponent)"
            } else {
                names = failure.url.lastPathComponent
            }
            return "\(names): \(failureReasonText(failure.reason))"
        }.joined(separator: "\n")
    }

    private func combinedValidationMessage(local: String?, plan: String?) -> String? {
        var seenLines: Set<String> = []
        let lines = [local, plan]
            .compactMap { $0 }
            .flatMap { $0.split(separator: "\n").map(String.init) }
            .filter { !$0.isEmpty && seenLines.insert($0).inserted }
        return lines.isEmpty ? nil : lines.joined(separator: "\n")
    }

    private func failureReasonText(_ reason: BatchFileFailureReason) -> String {
        switch reason {
        case .emptyName:
            return AppStrings.text("folderBrowser.failure.emptyName")
        case .invalidName:
            return AppStrings.text("folderBrowser.failure.invalidName")
        case .sourceMissing:
            return AppStrings.text("folderBrowser.failure.sourceMissing")
        case .destinationExists:
            return AppStrings.text("folderBrowser.failure.destinationExists")
        case .duplicateDestination:
            return AppStrings.text("folderBrowser.failure.duplicateDestination")
        case .trashFailed(let detail):
            return String(format: AppStrings.text("folderBrowser.failure.trashFailed"), detail)
        case .moveFailed(let detail):
            return String(format: AppStrings.text("folderBrowser.failure.moveFailed"), detail)
        case .renameFailed(let detail):
            return String(format: AppStrings.text("folderBrowser.failure.renameFailed"), detail)
        case .cancelled:
            return AppStrings.text("folderBrowser.failure.cancelled")
        }
    }

    private func closeSheet() {
        removeBackgroundClickMonitor()
        guard let window else { return }
        if let sheetParent = window.sheetParent {
            sheetParent.endSheet(window)
        } else {
            window.close()
        }
    }

    private func resizeToFitContent(maximumHeight: CGFloat = 600) {
        guard let window, contentStack.superview != nil else { return }
        window.contentView?.layoutSubtreeIfNeeded()
        let fittingSize = contentStack.fittingSize
        let width = min(max(fittingSize.width + 40, 480), 720)
        let height = min(max(fittingSize.height + 40, 220), maximumHeight)
        window.setContentSize(NSSize(width: width, height: height))
    }

    private func installBackgroundClickMonitor(for parentWindow: NSWindow) {
        removeBackgroundClickMonitor()
        backgroundClickMonitor = NSEvent.addLocalMonitorForEvents(matching: .leftMouseDown) { [weak self, weak parentWindow] event in
            guard let self, let parentWindow, event.window === parentWindow else { return event }
            return self.dismissForBackgroundClick(in: parentWindow) ? nil : event
        }
    }

    private func dismissForBackgroundClick(in parentWindow: NSWindow) -> Bool {
        guard window?.sheetParent === parentWindow else { return false }
        closeSheet()
        return true
    }

    private func removeBackgroundClickMonitor() {
        guard let backgroundClickMonitor else { return }
        NSEvent.removeMonitor(backgroundClickMonitor)
        self.backgroundClickMonitor = nil
    }

}

private enum ValidationResult {
    case valid(BatchRenameSheetController.RenameParameters)
    case invalid(String)
}
