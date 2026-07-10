import SwiftUI

struct CropControlsView: View {
    let onCancel: () -> Void
    let onApply: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Button("Cancel", action: onCancel)
                .keyboardShortcut(.cancelAction)
            Button("Apply", action: onApply)
                .keyboardShortcut(.defaultAction)
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.regular)
        .padding(8)
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}
