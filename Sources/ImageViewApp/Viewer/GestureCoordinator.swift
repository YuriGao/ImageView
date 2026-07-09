import AppKit

@MainActor
final class GestureCoordinator: NSObject {
    private weak var canvas: ImageCanvasView?

    init(canvas: ImageCanvasView) {
        self.canvas = canvas
        super.init()
        install()
    }

    private func install() {
        let magnification = NSMagnificationGestureRecognizer(target: self, action: #selector(handleMagnification(_:)))
        let pan = NSPanGestureRecognizer(target: self, action: #selector(handlePan(_:)))
        let click = NSClickGestureRecognizer(target: self, action: #selector(handleDoubleClick(_:)))
        click.numberOfClicksRequired = 2
        canvas?.addGestureRecognizer(magnification)
        canvas?.addGestureRecognizer(pan)
        canvas?.addGestureRecognizer(click)
    }

    func applyMagnification(_ magnification: CGFloat, at point: CGPoint) {
        canvas?.zoom(by: 1.0 + magnification, around: point)
    }

    func applyPan(translation: CGPoint, state: NSGestureRecognizer.State) {
        guard let canvas else { return }
        if canvas.scale > 1.01 {
            canvas.pan(by: CGPoint(x: translation.x, y: translation.y))
        } else if state == .ended {
            if translation.x < -80 { canvas.onNext?() }
            if translation.x > 80 { canvas.onPrevious?() }
        }
    }

    func applyDoubleClick() {
        canvas?.toggleFitOrActualSize()
    }

    @objc private func handleMagnification(_ gesture: NSMagnificationGestureRecognizer) {
        guard let canvas else { return }
        let point = gesture.location(in: canvas)
        applyMagnification(gesture.magnification, at: point)
        gesture.magnification = 0
    }

    @objc private func handlePan(_ gesture: NSPanGestureRecognizer) {
        guard let canvas else { return }
        let translation = gesture.translation(in: canvas)
        applyPan(translation: translation, state: gesture.state)
        gesture.setTranslation(.zero, in: canvas)
    }

    @objc private func handleDoubleClick(_ gesture: NSClickGestureRecognizer) {
        applyDoubleClick()
    }
}
