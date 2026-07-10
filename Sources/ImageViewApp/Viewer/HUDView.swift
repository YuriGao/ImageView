import SwiftUI

struct HUDView: View {
    let filename: String
    let positionText: String
    let zoomText: String
    let hasUnsavedEdits: Bool
    let isPinned: Bool

    var body: some View {
        HStack(spacing: 12) {
            Text(filename)
                .lineLimit(1)
                .truncationMode(.middle)
            Text(positionText)
            Text(zoomText)
            if hasUnsavedEdits {
                Text("Unsaved")
                    .font(.system(size: 10, weight: .semibold))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(.quaternary)
                    .clipShape(RoundedRectangle(cornerRadius: 5))
            }
        }
        .font(.system(size: 12, weight: .medium))
        .foregroundStyle(.primary)
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .opacity(isPinned ? 1.0 : 0.92)
    }
}
