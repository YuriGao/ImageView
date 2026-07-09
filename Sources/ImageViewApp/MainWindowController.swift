import AppKit
import Combine
import SwiftUI

@MainActor
final class MainWindowController: NSWindowController {
    enum KeyAction: Equatable {
        case showPrevious
        case showNext
        case toggleZoom
        case toggleFullscreen
        case endEditing
        case passThrough
    }

    private let viewModel = ViewerViewModel()
    private let rootView = NSView()
    private let canvas = ImageCanvasView()
    private let errorOverlay = ErrorOverlayView()
    private let hudView = NSHostingView(rootView: HUDView(filename: "ImageView", positionText: "0 / 0", zoomText: "100%", isPinned: true))
    private let filmstripView = FilmstripView()
    private var cancellables: Set<AnyCancellable> = []
    private var gestureCoordinator: GestureCoordinator?
    private var keyMonitor: Any?
    private var displayedItemURL: URL?

    convenience init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1100, height: 760),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.title = "ImageView"
        self.init(window: window)
        setup()
    }

    func open(url: URL) {
        Task { await viewModel.open(url: url) }
    }

    private func setup() {
        window?.titlebarAppearsTransparent = true
        window?.center()
        rootView.wantsLayer = true
        canvas.autoresizingMask = [.width, .height]
        canvas.translatesAutoresizingMaskIntoConstraints = false
        window?.contentView = rootView
        rootView.addSubview(canvas)
        canvas.addSubview(errorOverlay)
        rootView.addSubview(hudView)
        rootView.addSubview(filmstripView)
        errorOverlay.translatesAutoresizingMaskIntoConstraints = false
        hudView.translatesAutoresizingMaskIntoConstraints = false
        filmstripView.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            canvas.leadingAnchor.constraint(equalTo: rootView.leadingAnchor),
            canvas.trailingAnchor.constraint(equalTo: rootView.trailingAnchor),
            canvas.topAnchor.constraint(equalTo: rootView.topAnchor),
            canvas.bottomAnchor.constraint(equalTo: rootView.bottomAnchor),
            errorOverlay.centerXAnchor.constraint(equalTo: canvas.centerXAnchor),
            errorOverlay.centerYAnchor.constraint(equalTo: canvas.centerYAnchor),
            hudView.topAnchor.constraint(equalTo: rootView.topAnchor, constant: 18),
            hudView.centerXAnchor.constraint(equalTo: rootView.centerXAnchor),
            hudView.leadingAnchor.constraint(greaterThanOrEqualTo: rootView.leadingAnchor, constant: 16),
            hudView.trailingAnchor.constraint(lessThanOrEqualTo: rootView.trailingAnchor, constant: -16),
            filmstripView.leadingAnchor.constraint(equalTo: rootView.leadingAnchor, constant: 16),
            filmstripView.trailingAnchor.constraint(equalTo: rootView.trailingAnchor, constant: -16),
            filmstripView.bottomAnchor.constraint(equalTo: rootView.bottomAnchor, constant: -16),
            filmstripView.heightAnchor.constraint(equalToConstant: 36)
        ])

        canvas.onNext = { [weak self] in self?.viewModel.showNext() }
        canvas.onPrevious = { [weak self] in self?.viewModel.showPrevious() }
        canvas.onTransformChanged = { [weak self] scale in
            self?.updateHUD(zoomScale: scale)
        }
        gestureCoordinator = GestureCoordinator(canvas: canvas)
        filmstripView.onSelect = { [weak self] item in
            self?.viewModel.show(item: item)
        }

        viewModel.$currentImage
            .sink { [weak self] image in
                self?.canvas.image = image
            }
            .store(in: &cancellables)

        viewModel.$displayTitle
            .sink { [weak self] title in
                self?.window?.title = title
            }
            .store(in: &cancellables)

        viewModel.$errorMessage
            .sink { [weak self] message in
                self?.errorOverlay.stringValue = message ?? ""
            }
            .store(in: &cancellables)

        viewModel.$navigationState
            .sink { [weak self] state in
                guard let self else { return }
                let newURL = state?.currentItem?.url
                if Self.shouldResetCanvasTransform(from: self.displayedItemURL, to: newURL) {
                    self.canvas.resetViewTransform()
                }
                self.displayedItemURL = newURL?.standardizedFileURL
                self.filmstripView.apply(items: state?.items ?? [], current: state?.currentItem)
                self.updateHUD()
            }
            .store(in: &cancellables)

        installKeyMonitor()
        updateHUD()
    }

    override func keyDown(with event: NSEvent) {
        guard !handleKeyDown(event) else { return }
        super.keyDown(with: event)
    }

    private func installKeyMonitor() {
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, self.window?.isKeyWindow == true else {
                return event
            }
            return self.handleKeyDown(event) ? nil : event
        }
    }

    private func handleKeyDown(_ event: NSEvent) -> Bool {
        switch Self.keyAction(for: event.keyCode, shouldEndEditing: shouldEndEditing(for: event)) {
        case .showPrevious:
            viewModel.showPrevious()
            return true
        case .showNext:
            viewModel.showNext()
            return true
        case .toggleZoom:
            canvas.toggleFitOrActualSize()
            return true
        case .toggleFullscreen:
            window?.toggleFullScreen(nil)
            return true
        case .endEditing:
            window?.endEditing(for: nil)
            return true
        case .passThrough:
            return false
        }
    }

    private func shouldEndEditing(for event: NSEvent) -> Bool {
        guard event.keyCode == 53,
              let window,
              let responder = window.firstResponder else {
            return false
        }

        return responder is NSText || responder is NSTextView
    }

    static func keyAction(for keyCode: UInt16, shouldEndEditing: Bool) -> KeyAction {
        switch keyCode {
        case 123:
            return .showPrevious
        case 124:
            return .showNext
        case 49:
            return .toggleZoom
        case 36:
            return .toggleFullscreen
        case 53:
            return shouldEndEditing ? .endEditing : .passThrough
        default:
            return .passThrough
        }
    }

    static func shouldResetCanvasTransform(from previousURL: URL?, to newURL: URL?) -> Bool {
        previousURL?.standardizedFileURL != newURL?.standardizedFileURL
    }

    private func updateHUD(zoomScale: CGFloat? = nil) {
        let scale = zoomScale ?? canvas.scale
        hudView.rootView = HUDView(
            filename: viewModel.currentFilename,
            positionText: viewModel.positionText,
            zoomText: "\(Int((scale * 100).rounded()))%",
            isPinned: true
        )
    }
}
