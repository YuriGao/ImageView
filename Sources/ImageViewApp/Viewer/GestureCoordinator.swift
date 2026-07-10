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
        let click = NSClickGestureRecognizer(target: self, action: #selector(handleDoubleClick(_:)))
        click.numberOfClicksRequired = 2
        let twoFingerTap = NSClickGestureRecognizer(target: self, action: #selector(handleTwoFingerTap(_:)))
        twoFingerTap.numberOfTouchesRequired = 2
        canvas?.addGestureRecognizer(magnification)
        canvas?.addGestureRecognizer(click)
        canvas?.addGestureRecognizer(twoFingerTap)
    }

    func applyMagnification(_ magnification: CGFloat, at point: CGPoint) {
        canvas?.zoom(by: 1.0 + magnification, around: point)
    }

    func applyDoubleClick() {
        canvas?.toggleFitOrActualSize()
    }

    func applyTwoFingerTap() {
        canvas?.toggleFitOrActualSize()
    }

    @objc private func handleMagnification(_ gesture: NSMagnificationGestureRecognizer) {
        guard let canvas else { return }
        let point = gesture.location(in: canvas)
        applyMagnification(gesture.magnification, at: point)
        gesture.magnification = 0
    }

    @objc private func handleDoubleClick(_ gesture: NSClickGestureRecognizer) {
        applyDoubleClick()
    }

    @objc private func handleTwoFingerTap(_ gesture: NSClickGestureRecognizer) {
        applyTwoFingerTap()
    }
}
