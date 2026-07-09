import AppKit
import Combine

final class MainWindowController: NSWindowController {
    private let viewModel = ViewerViewModel()
    private let canvas = ImageCanvasView()
    private let errorOverlay = ErrorOverlayView()
    private var cancellables: Set<AnyCancellable> = []

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
        canvas.autoresizingMask = [.width, .height]
        window?.contentView = canvas
        canvas.addSubview(errorOverlay)
        errorOverlay.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            errorOverlay.centerXAnchor.constraint(equalTo: canvas.centerXAnchor),
            errorOverlay.centerYAnchor.constraint(equalTo: canvas.centerYAnchor)
        ])

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
    }
}
