import AppKit
import ImageViewCore

@MainActor
final class BatchRenameSheetController: NSWindowController {
    struct RenameParameters: Equatable {
        let baseName: String
        let startNumber: Int
        let padding: Int
    }

    struct PreviewRow: Equatable {
        let oldName: String
        let newName: String
    }

    var onConfirm: ((RenameParameters) -> Void)?

    private let items: [ImageItem]
    private let baseNameField = NSTextField(string: AppStrings.text("batchRename.defaultBaseName"))
    private let startNumberField = NSTextField(string: "1")
    private let paddingField = NSTextField(string: "2")
    private let previewStack = NSStackView()
    private let errorLabel = NSTextField(labelWithString: "")
    private let renameButton = NSButton(title: AppStrings.text("batchRename.button.rename"), target: nil, action: nil)

    var previewRowsForTesting: [PreviewRow] {
        previewRows()
    }
    var validationErrorForTesting: String? {
        errorLabel.isHidden ? nil : errorLabel.stringValue
    }

    init(items: [ImageItem]) {
        self.items = items
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

    private func buildView() {
        guard let window else { return }

        let content = NSStackView()
        content.orientation = .vertical
        content.alignment = .leading
        content.spacing = 12
        content.translatesAutoresizingMaskIntoConstraints = false

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
            field.target = self
            field.action = #selector(inputChanged(_:))
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

        content.addArrangedSubview(title)
        content.addArrangedSubview(form)
        content.addArrangedSubview(errorLabel)
        content.addArrangedSubview(previewTitle)
        content.addArrangedSubview(previewStack)
        content.addArrangedSubview(buttonStack)
        window.contentView = NSView()
        window.contentView?.addSubview(content)

        NSLayoutConstraint.activate([
            content.leadingAnchor.constraint(equalTo: window.contentView!.leadingAnchor, constant: 20),
            content.trailingAnchor.constraint(lessThanOrEqualTo: window.contentView!.trailingAnchor, constant: -20),
            content.topAnchor.constraint(equalTo: window.contentView!.topAnchor, constant: 20),
            content.bottomAnchor.constraint(lessThanOrEqualTo: window.contentView!.bottomAnchor, constant: -20),
            baseNameField.widthAnchor.constraint(equalToConstant: 260),
            startNumberField.widthAnchor.constraint(equalToConstant: 80),
            paddingField.widthAnchor.constraint(equalToConstant: 80)
        ])
    }

    @objc private func inputChanged(_ sender: Any?) {
        errorLabel.isHidden = true
        updatePreview()
    }

    @objc private func cancel(_ sender: Any?) {
        closeSheet()
    }

    @objc private func confirm(_ sender: Any?) {
        switch validateParameters() {
        case .valid(let parameters):
            onConfirm?(parameters)
        case .invalid(let message):
            errorLabel.stringValue = message
            errorLabel.isHidden = false
            return
        }
        closeSheet()
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
        let parameters = parameters()
        let trimmedBaseName = parameters.baseName.trimmingCharacters(in: .whitespacesAndNewlines)
        return items.enumerated().map { offset, item in
            let number = parameters.startNumber + offset
            let formattedNumber = parameters.padding > 0
                ? String(format: "%0\(parameters.padding)d", number)
                : "\(number)"
            var newName = "\(trimmedBaseName) \(formattedNumber)"
            if !item.url.pathExtension.isEmpty {
                newName += ".\(item.url.pathExtension)"
            }
            return PreviewRow(oldName: item.url.lastPathComponent, newName: newName)
        }
    }

    private func updatePreview() {
        previewStack.arrangedSubviews.forEach {
            previewStack.removeArrangedSubview($0)
            $0.removeFromSuperview()
        }

        for row in previewRows().prefix(8) {
            previewStack.addArrangedSubview(NSTextField(labelWithString: "\(row.oldName) → \(row.newName)"))
        }
    }

    private func closeSheet() {
        guard let window else { return }
        if let sheetParent = window.sheetParent {
            sheetParent.endSheet(window)
        } else {
            window.close()
        }
    }
}

private enum ValidationResult {
    case valid(BatchRenameSheetController.RenameParameters)
    case invalid(String)
}
