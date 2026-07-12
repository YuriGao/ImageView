import SwiftUI

struct CropControlsView: View {
    let onCancel: () -> Void
    let onApply: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Button(AppStrings.text("crop.button.cancel"), action: onCancel)
                .keyboardShortcut(.cancelAction)
            Button(AppStrings.text("crop.button.apply"), action: onApply)
                .keyboardShortcut(.defaultAction)
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.regular)
        .padding(8)
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}
