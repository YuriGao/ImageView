import SwiftUI

struct HUDView: View {
    let filename: String
    let positionText: String
    let zoomText: String
    let isPinned: Bool

    var body: some View {
        HStack(spacing: 12) {
            Text(filename)
                .lineLimit(1)
            Text(positionText)
            Text(zoomText)
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
