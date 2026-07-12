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
    private let baseNameField = NSTextField(string: "Image")
    private let startNumberField = NSTextField(string: "1")
    private let paddingField = NSTextField(string: "2")
    private let previewStack = NSStackView()

    var previewRowsForTesting: [PreviewRow] {
        previewRows()
    }

    init(items: [ImageItem]) {
        self.items = items
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 480, height: 360),
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )
        window.title = "Batch Rename"
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

        let title = NSTextField(labelWithString: "Batch Rename")
        title.font = .systemFont(ofSize: 18, weight: .semibold)

        let form = NSGridView(views: [
            [NSTextField(labelWithString: "Base name"), baseNameField],
            [NSTextField(labelWithString: "Start number"), startNumberField],
            [NSTextField(labelWithString: "Padding"), paddingField]
        ])
        form.rowSpacing = 8
        form.columnSpacing = 12
        form.translatesAutoresizingMaskIntoConstraints = false
        for field in [baseNameField, startNumberField, paddingField] {
            field.target = self
            field.action = #selector(inputChanged(_:))
        }

        let previewTitle = NSTextField(labelWithString: "Preview")
        previewTitle.font = .systemFont(ofSize: 13, weight: .semibold)

        previewStack.orientation = .vertical
        previewStack.alignment = .leading
        previewStack.spacing = 4
        previewStack.translatesAutoresizingMaskIntoConstraints = false

        let buttonStack = NSStackView()
        buttonStack.orientation = .horizontal
        buttonStack.alignment = .centerY
        buttonStack.spacing = 8
        let cancelButton = NSButton(title: "Cancel", target: self, action: #selector(cancel(_:)))
        let renameButton = NSButton(title: "Rename", target: self, action: #selector(confirm(_:)))
        renameButton.keyEquivalent = "\r"
        buttonStack.addArrangedSubview(cancelButton)
        buttonStack.addArrangedSubview(renameButton)

        content.addArrangedSubview(title)
        content.addArrangedSubview(form)
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
        updatePreview()
    }

    @objc private func cancel(_ sender: Any?) {
        closeSheet()
    }

    @objc private func confirm(_ sender: Any?) {
        onConfirm?(parameters())
        closeSheet()
    }

    private func parameters() -> RenameParameters {
        RenameParameters(
            baseName: baseNameField.stringValue,
            startNumber: max(0, startNumberField.integerValue),
            padding: max(0, paddingField.integerValue)
        )
    }

    private func previewRows() -> [PreviewRow] {
        let parameters = parameters()
        return items.enumerated().map { offset, item in
            let number = parameters.startNumber + offset
            let formattedNumber = parameters.padding > 0
                ? String(format: "%0\(parameters.padding)d", number)
                : "\(number)"
            var newName = "\(parameters.baseName) \(formattedNumber)"
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
