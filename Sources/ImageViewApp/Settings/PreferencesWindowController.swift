import AppKit
import Combine
import ImageViewCore

@MainActor
final class PreferencesWindowController: NSWindowController {
    private let settings: AppSettings
    private let preferredLanguages: [String]
    private let fileAssociationModel: FileAssociationSettingsModel
    private var cancellables: Set<AnyCancellable> = []

    private let showsFilmstripButton = NSButton()
    private let showsInspectorButton = NSButton()
    private let confirmsDeleteButton = NSButton()
    private let navigationTransitionsButton = NSButton()
    private let rowsStack = NSStackView()
    private let selectCommonButton = NSButton()
    private let showAllButton = NSButton()
    private let applyButton = NSButton()
    private let summaryLabel = NSTextField(labelWithString: "")
    private var rowControls: [SupportedImageFormat: (checkbox: NSButton, status: NSTextField)] = [:]
    private var renderedFormats: [SupportedImageFormat] = []

    init(
        settings: AppSettings = .shared,
        defaultApplicationService: DefaultApplicationServicing = WorkspaceDefaultApplicationService(),
        applicationURL: @escaping () -> URL? = { Bundle.main.bundleURL },
        preferredLanguages: [String] = Locale.preferredLanguages
    ) {
        self.settings = settings
        self.preferredLanguages = preferredLanguages
        self.fileAssociationModel = FileAssociationSettingsModel(
            service: defaultApplicationService,
            applicationURL: applicationURL
        )
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 560, height: 620),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = AppStrings.text("settings.title", preferredLanguages: preferredLanguages)
        super.init(window: window)
        setup()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

    override func showWindow(_ sender: Any?) {
        fileAssociationModel.refreshStatuses()
        render()
        window?.center()
        super.showWindow(sender)
    }

    private func text(_ key: String) -> String {
        AppStrings.text(key, preferredLanguages: preferredLanguages)
    }

    private func heading(_ title: String, identifier: String? = nil) -> NSTextField {
        let label = NSTextField(labelWithString: title)
        label.font = .systemFont(ofSize: NSFont.systemFontSize, weight: .semibold)
        if let identifier { label.identifier = NSUserInterfaceItemIdentifier(identifier) }
        return label
    }

    private func setup() {
        guard let window else { return }
        configureGeneralButton(showsFilmstripButton, key: "settings.general.showsFilmstrip", identifier: "settings.showsFilmstrip")
        configureGeneralButton(showsInspectorButton, key: "settings.general.showsInspector", identifier: "settings.showsInspector")
        configureGeneralButton(confirmsDeleteButton, key: "settings.general.confirmsDelete", identifier: "settings.confirmsDelete")
        configureGeneralButton(navigationTransitionsButton, key: "settings.general.navigationTransitions", identifier: "settings.navigationTransitions")
        let generalStack = NSStackView(views: [
            showsFilmstripButton, showsInspectorButton,
            confirmsDeleteButton, navigationTransitionsButton
        ])
        generalStack.orientation = .vertical
        generalStack.alignment = .leading
        generalStack.spacing = 8

        let separator = NSBox()
        separator.boxType = .separator

        selectCommonButton.title = text("settings.fileAssociations.selectCommon")
        selectCommonButton.bezelStyle = .rounded
        selectCommonButton.target = self
        selectCommonButton.action = #selector(selectCommonFormats(_:))

        showAllButton.title = text("settings.fileAssociations.showAll")
        showAllButton.identifier = NSUserInterfaceItemIdentifier("fileAssociation.showAll")
        showAllButton.bezelStyle = .inline
        showAllButton.target = self
        showAllButton.action = #selector(toggleShowsAllFormats(_:))

        let actions = NSStackView(views: [selectCommonButton, showAllButton])
        actions.orientation = .horizontal
        actions.alignment = .centerY
        actions.spacing = 12

        rowsStack.orientation = .vertical
        rowsStack.alignment = .leading
        rowsStack.spacing = 8

        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.drawsBackground = false
        scrollView.documentView = rowsStack
        rowsStack.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            rowsStack.leadingAnchor.constraint(equalTo: scrollView.contentView.leadingAnchor),
            rowsStack.trailingAnchor.constraint(equalTo: scrollView.contentView.trailingAnchor),
            rowsStack.topAnchor.constraint(equalTo: scrollView.contentView.topAnchor),
            rowsStack.widthAnchor.constraint(equalTo: scrollView.contentView.widthAnchor)
        ])

        applyButton.identifier = NSUserInterfaceItemIdentifier("fileAssociation.apply")
        applyButton.bezelStyle = .rounded
        applyButton.keyEquivalent = "\r"
        applyButton.target = self
        applyButton.action = #selector(applySelectedFormats(_:))
        summaryLabel.textColor = .secondaryLabelColor
        summaryLabel.lineBreakMode = .byWordWrapping
        summaryLabel.maximumNumberOfLines = 2

        let footer = NSStackView(views: [summaryLabel, applyButton])
        footer.orientation = .horizontal
        footer.alignment = .centerY
        footer.spacing = 12
        summaryLabel.setContentHuggingPriority(.defaultLow, for: .horizontal)
        applyButton.setContentHuggingPriority(.required, for: .horizontal)

        let contentStack = NSStackView(views: [
            heading(text("settings.general.title")), generalStack, separator,
            heading(text("settings.fileAssociations.title"), identifier: "fileAssociation.title"),
            actions, scrollView, footer
        ])
        contentStack.orientation = .vertical
        contentStack.alignment = .leading
        contentStack.spacing = 12
        contentStack.translatesAutoresizingMaskIntoConstraints = false

        let contentView = NSView()
        contentView.addSubview(contentStack)
        window.contentView = contentView
        NSLayoutConstraint.activate([
            contentStack.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 24),
            contentStack.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -24),
            contentStack.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 20),
            contentStack.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -20),
            separator.widthAnchor.constraint(equalTo: contentStack.widthAnchor),
            scrollView.widthAnchor.constraint(equalTo: contentStack.widthAnchor),
            scrollView.heightAnchor.constraint(greaterThanOrEqualToConstant: 230),
            footer.widthAnchor.constraint(equalTo: contentStack.widthAnchor)
        ])

        showsFilmstripButton.target = self
        showsFilmstripButton.action = #selector(toggleShowsFilmstrip(_:))
        showsInspectorButton.target = self
        showsInspectorButton.action = #selector(toggleShowsInspector(_:))
        confirmsDeleteButton.target = self
        confirmsDeleteButton.action = #selector(toggleConfirmsDelete(_:))
        navigationTransitionsButton.target = self
        navigationTransitionsButton.action = #selector(toggleNavigationTransitions(_:))

        settings.objectWillChange
            .sink { [weak self] _ in
                Task { @MainActor [weak self] in self?.syncGeneralControls() }
            }
            .store(in: &cancellables)
        fileAssociationModel.objectWillChange
            .sink { [weak self] _ in
                Task { @MainActor [weak self] in self?.render() }
            }
            .store(in: &cancellables)
        syncGeneralControls()
        render()
    }

    private func rebuildRowsIfNeeded() {
        let formats = fileAssociationModel.visibleFormats
        guard renderedFormats != formats else { return }
        rowsStack.arrangedSubviews.forEach { view in
            rowsStack.removeArrangedSubview(view)
            view.removeFromSuperview()
        }
        rowControls.removeAll()
        renderedFormats = formats

        for format in formats {
            let checkbox = NSButton(checkboxWithTitle: text("settings.format.\(format.rawValue)"), target: self, action: #selector(toggleFormat(_:)))
            checkbox.identifier = NSUserInterfaceItemIdentifier("fileAssociation.\(format.rawValue).checkbox")
            checkbox.cell?.representedObject = format.rawValue
            checkbox.setContentHuggingPriority(.required, for: .horizontal)
            let extensions = NSTextField(labelWithString: extensionLabel(for: format))
            extensions.identifier = NSUserInterfaceItemIdentifier("fileAssociation.\(format.rawValue).extensions")
            extensions.textColor = .secondaryLabelColor
            extensions.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
            extensions.setContentHuggingPriority(.required, for: .horizontal)
            let status = NSTextField(labelWithString: "")
            status.identifier = NSUserInterfaceItemIdentifier("fileAssociation.\(format.rawValue).status")
            status.alignment = .right
            status.lineBreakMode = .byTruncatingMiddle
            status.setContentHuggingPriority(.defaultLow, for: .horizontal)
            let row = NSStackView(views: [checkbox, extensions, status])
            row.orientation = .horizontal
            row.alignment = .centerY
            row.spacing = 10
            row.identifier = NSUserInterfaceItemIdentifier("fileAssociation.\(format.rawValue)")
            rowsStack.addArrangedSubview(row)
            row.widthAnchor.constraint(equalTo: rowsStack.widthAnchor).isActive = true
            rowControls[format] = (checkbox, status)
        }
    }

    private func render() {
        rebuildRowsIfNeeded()
        let mutationsEnabled = !fileAssociationModel.isApplying
        for format in renderedFormats {
            guard let controls = rowControls[format] else { continue }
            controls.checkbox.state = fileAssociationModel.selectedFormats.contains(format) ? .on : .off
            controls.checkbox.isEnabled = mutationsEnabled
            let row = fileAssociationModel.rows[format]
            if let error = row?.error {
                switch error {
                case .unsupportedContentType:
                    controls.status.stringValue = text("settings.fileAssociations.unsupportedType")
                case .service(let description):
                    controls.status.stringValue = description
                }
                controls.status.textColor = .systemRed
            } else if row?.isImageViewDefault == true {
                controls.status.stringValue = text("settings.fileAssociations.defaultImageView")
                controls.status.textColor = .secondaryLabelColor
            } else if let name = row?.defaultApplicationName {
                controls.status.stringValue = localizedFormat("settings.fileAssociations.defaultOther", name)
                controls.status.textColor = .secondaryLabelColor
            } else {
                controls.status.stringValue = text("settings.fileAssociations.defaultUnknown")
                controls.status.textColor = .secondaryLabelColor
            }
        }
        selectCommonButton.isEnabled = mutationsEnabled
        showAllButton.isEnabled = mutationsEnabled
        showsFilmstripButton.isEnabled = mutationsEnabled
        showsInspectorButton.isEnabled = mutationsEnabled
        confirmsDeleteButton.isEnabled = mutationsEnabled
        navigationTransitionsButton.isEnabled = mutationsEnabled
        showAllButton.title = text(fileAssociationModel.showsAllFormats ? "settings.fileAssociations.showLess" : "settings.fileAssociations.showAll")
        applyButton.isEnabled = fileAssociationModel.canApply
        applyButton.title = text(fileAssociationModel.isApplying ? "settings.fileAssociations.applying" : "settings.fileAssociations.apply")
        summaryLabel.stringValue = summaryText()
    }

    private func localizedFormat(_ key: String, _ arguments: CVarArg...) -> String {
        String(format: text(key), locale: Locale(identifier: preferredLanguages.first ?? "en"), arguments: arguments)
    }

    private func summaryText() -> String {
        switch fileAssociationModel.summary {
        case .success(let count): return localizedFormat("settings.fileAssociations.success", count)
        case .partialSuccess(let succeeded, let failed): return localizedFormat("settings.fileAssociations.partialSuccess", succeeded, failed)
        case .failure(let count): return localizedFormat("settings.fileAssociations.failure", count)
        case .invalidApplicationBundle: return text("settings.fileAssociations.invalidBundle")
        case nil: return ""
        }
    }

    private func extensionLabel(for format: SupportedImageFormat) -> String {
        switch format {
        case .jpeg: return "JPG, JPEG"
        case .png: return "PNG"
        case .gif: return "GIF"
        case .webp: return "WEBP"
        case .heic: return "HEIC"
        case .tiff: return "TIF, TIFF"
        case .bmp: return "BMP"
        case .heif: return "HEIF"
        case .avif: return "AVIF"
        case .svg: return "SVG"
        }
    }

    private func configureGeneralButton(_ button: NSButton, key: String, identifier: String) {
        button.setButtonType(.switch)
        button.title = text(key)
        button.identifier = NSUserInterfaceItemIdentifier(identifier)
    }

    private func syncGeneralControls() {
        showsFilmstripButton.state = settings.showsFilmstrip ? .on : .off
        showsInspectorButton.state = settings.showsInspector ? .on : .off
        confirmsDeleteButton.state = settings.confirmsDelete ? .on : .off
        navigationTransitionsButton.state = settings.animatesNavigationTransitions ? .on : .off
    }

    @objc private func toggleFormat(_ sender: NSButton) {
        guard let rawValue = sender.cell?.representedObject as? String,
              let format = SupportedImageFormat(rawValue: rawValue) else { return }
        fileAssociationModel.toggleSelection(for: format)
        render()
    }

    @objc private func selectCommonFormats(_ sender: NSButton) {
        fileAssociationModel.selectCommonFormats()
        render()
    }

    @objc private func toggleShowsAllFormats(_ sender: NSButton) {
        fileAssociationModel.setShowsAllFormats(!fileAssociationModel.showsAllFormats)
        render()
    }

    @objc private func applySelectedFormats(_ sender: NSButton) {
        Task { @MainActor [weak self] in
            guard let self else { return }
            await fileAssociationModel.applySelectedFormats()
            render()
        }
    }

    @objc private func toggleShowsFilmstrip(_ sender: NSButton) { settings.showsFilmstrip = sender.state == .on }
    @objc private func toggleShowsInspector(_ sender: NSButton) { settings.showsInspector = sender.state == .on }
    @objc private func toggleConfirmsDelete(_ sender: NSButton) { settings.confirmsDelete = sender.state == .on }
    @objc private func toggleNavigationTransitions(_ sender: NSButton) { settings.animatesNavigationTransitions = sender.state == .on }
}
