import CoreGraphics

public enum EditOperation: Equatable, Sendable {
    case rotateClockwise
    case rotateCounterClockwise
    case mirrorHorizontal
    case mirrorVertical
    case crop(CGRect)
}
