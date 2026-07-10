import AppKit
import Combine

@MainActor
final class PreferencesWindowController: NSWindowController {
    private let settings: AppSettings
    private var cancellables: Set<AnyCancellable> = []
    private let pinsHUDButton = NSButton(checkboxWithTitle: "Pin HUD", target: nil, action: nil)
    private let showsFilmstripButton = NSButton(checkboxWithTitle: "Show filmstrip", target: nil, action: nil)
    private let showsInspectorButton = NSButton(checkboxWithTitle: "Show info panel", target: nil, action: nil)
    private let confirmsDeleteButton = NSButton(checkboxWithTitle: "Confirm before moving to Trash", target: nil, action: nil)
    private let blackFullscreenBackgroundButton = NSButton(checkboxWithTitle: "Use black fullscreen background", target: nil, action: nil)
    private let navigationTransitionsButton = NSButton(checkboxWithTitle: "Animate image transitions", target: nil, action: nil)

    init(settings: AppSettings = .shared) {
        self.settings = settings
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 360, height: 240),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "ImageView Settings"
        super.init(window: window)
        setup()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
    }

    override func showWindow(_ sender: Any?) {
        syncControls()
        window?.center()
        super.showWindow(sender)
    }

    private func setup() {
        guard let window else { return }
        let stack = NSStackView(views: [
            pinsHUDButton,
            showsFilmstripButton,
            showsInspectorButton,
            confirmsDeleteButton,
            blackFullscreenBackgroundButton,
            navigationTransitionsButton
        ])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 14
        stack.translatesAutoresizingMaskIntoConstraints = false

        let contentView = NSView()
        contentView.addSubview(stack)
        window.contentView = contentView
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 24),
            stack.trailingAnchor.constraint(lessThanOrEqualTo: contentView.trailingAnchor, constant: -24),
            stack.centerYAnchor.constraint(equalTo: contentView.centerYAnchor)
        ])

        pinsHUDButton.target = self
        pinsHUDButton.action = #selector(togglePinsHUD(_:))
        showsFilmstripButton.target = self
        showsFilmstripButton.action = #selector(toggleShowsFilmstrip(_:))
        showsInspectorButton.target = self
        showsInspectorButton.action = #selector(toggleShowsInspector(_:))
        confirmsDeleteButton.target = self
        confirmsDeleteButton.action = #selector(toggleConfirmsDelete(_:))
        blackFullscreenBackgroundButton.target = self
        blackFullscreenBackgroundButton.action = #selector(toggleBlackFullscreenBackground(_:))
        navigationTransitionsButton.target = self
        navigationTransitionsButton.action = #selector(toggleNavigationTransitions(_:))

        settings.objectWillChange
            .sink { [weak self] _ in
                Task { @MainActor [weak self] in
                    self?.syncControls()
                }
            }
            .store(in: &cancellables)
        syncControls()
    }

    private func syncControls() {
        pinsHUDButton.state = settings.pinsHUD ? .on : .off
        showsFilmstripButton.state = settings.showsFilmstrip ? .on : .off
        showsInspectorButton.state = settings.showsInspector ? .on : .off
        confirmsDeleteButton.state = settings.confirmsDelete ? .on : .off
        blackFullscreenBackgroundButton.state = settings.usesBlackFullscreenBackground ? .on : .off
        navigationTransitionsButton.state = settings.animatesNavigationTransitions ? .on : .off
    }

    @objc private func togglePinsHUD(_ sender: NSButton) {
        settings.pinsHUD = sender.state == .on
    }

    @objc private func toggleShowsFilmstrip(_ sender: NSButton) {
        settings.showsFilmstrip = sender.state == .on
    }

    @objc private func toggleShowsInspector(_ sender: NSButton) {
        settings.showsInspector = sender.state == .on
    }

    @objc private func toggleConfirmsDelete(_ sender: NSButton) {
        settings.confirmsDelete = sender.state == .on
    }

    @objc private func toggleBlackFullscreenBackground(_ sender: NSButton) {
        settings.usesBlackFullscreenBackground = sender.state == .on
    }

    @objc private func toggleNavigationTransitions(_ sender: NSButton) {
        settings.animatesNavigationTransitions = sender.state == .on
    }
}
