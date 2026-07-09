import AppKit
import Combine
import SwiftUI

@MainActor
final class MainWindowController: NSWindowController {
    private let viewModel = ViewerViewModel()
    private let rootView = NSView()
    private let canvas = ImageCanvasView()
    private let errorOverlay = ErrorOverlayView()
    private let hudView = NSHostingView(rootView: HUDView(filename: "ImageView", positionText: "0 / 0", zoomText: "100%", isPinned: true))
    private let filmstripView = FilmstripView()
    private var cancellables: Set<AnyCancellable> = []
    private var gestureCoordinator: GestureCoordinator?
    private var keyMonitor: Any?

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
                self?.filmstripView.apply(items: state?.items ?? [], current: state?.currentItem)
                self?.updateHUD()
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
        switch event.keyCode {
        case 123:
            viewModel.showPrevious()
            return true
        case 124:
            viewModel.showNext()
            return true
        case 49:
            canvas.toggleFitOrActualSize()
            return true
        case 36:
            window?.toggleFullScreen(nil)
            return true
        case 53:
            window?.endEditing(for: nil)
            return true
        default:
            return false
        }
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
