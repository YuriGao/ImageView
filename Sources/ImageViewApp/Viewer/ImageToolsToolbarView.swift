import SwiftUI

struct ImageToolsToolbarState: Equatable {
    let canShowPrevious: Bool
    let canShowNext: Bool
    let canEdit: Bool
    let canMoveToTrash: Bool
    let isVisible: Bool

    static func state(
        hasImage: Bool,
        position: Int?,
        itemCount: Int,
        isCropping: Bool
    ) -> ImageToolsToolbarState {
        let validPosition = position.flatMap { index in
            itemCount > 0 && (0..<itemCount).contains(index) ? index : nil
        }
        return ImageToolsToolbarState(
            canShowPrevious: validPosition.map { $0 > 0 } ?? false,
            canShowNext: validPosition.map { $0 < itemCount - 1 } ?? false,
            canEdit: hasImage,
            canMoveToTrash: hasImage,
            isVisible: !isCropping
        )
    }
}

struct ImageToolsToolbarView: View {
    let state: ImageToolsToolbarState
    let onPrevious: () -> Void
    let onNext: () -> Void
    let onRotate: () -> Void
    let onCrop: () -> Void
    let onMirror: () -> Void
    let onTrash: () -> Void

    var body: some View {
        HStack(spacing: 4) {
            toolButton("chevron.left", label: "Previous Image", isEnabled: state.canShowPrevious, action: onPrevious)
            toolButton("chevron.right", label: "Next Image", isEnabled: state.canShowNext, action: onNext)
            Divider().frame(height: 18)
            toolButton("rotate.right", label: "Rotate Clockwise", isEnabled: state.canEdit, action: onRotate)
            toolButton("crop", label: "Crop", isEnabled: state.canEdit, action: onCrop)
            toolButton("rectangle.lefthalf.inset.filled", label: "Flip Horizontal", isEnabled: state.canEdit, action: onMirror)
            Divider().frame(height: 18)
            toolButton("trash", label: "Move to Trash", isEnabled: state.canMoveToTrash, action: onTrash)
        }
        .padding(6)
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .opacity(state.isVisible ? 1 : 0)
    }

    private func toolButton(
        _ symbolName: String,
        label: String,
        isEnabled: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: symbolName)
                .frame(width: 28, height: 24)
        }
        .buttonStyle(.borderless)
        .disabled(!isEnabled)
        .help(label)
        .accessibilityLabel(label)
    }
}
