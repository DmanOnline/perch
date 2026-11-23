import SwiftUI

/// A notch body with flared top corners, so it melts into the menu bar,
/// and rounded bottom corners. `rect` includes the ears on both sides.
nonisolated struct NotchShape: Shape {
    var earRadius: CGFloat
    var bottomRadius: CGFloat

    var animatableData: AnimatablePair<CGFloat, CGFloat> {
        get { AnimatablePair(earRadius, bottomRadius) }
        set {
            earRadius = newValue.first
            bottomRadius = newValue.second
        }
    }

    func path(in rect: CGRect) -> Path {
        let ear = min(earRadius, rect.width / 4)
        let bottom = min(bottomRadius, (rect.width - 2 * ear) / 2, rect.height - ear)
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addQuadCurve(
            to: CGPoint(x: rect.minX + ear, y: rect.minY + ear),
            control: CGPoint(x: rect.minX + ear, y: rect.minY)
        )
        path.addLine(to: CGPoint(x: rect.minX + ear, y: rect.maxY - bottom))
        path.addQuadCurve(
            to: CGPoint(x: rect.minX + ear + bottom, y: rect.maxY),
            control: CGPoint(x: rect.minX + ear, y: rect.maxY)
        )
        path.addLine(to: CGPoint(x: rect.maxX - ear - bottom, y: rect.maxY))
        path.addQuadCurve(
            to: CGPoint(x: rect.maxX - ear, y: rect.maxY - bottom),
            control: CGPoint(x: rect.maxX - ear, y: rect.maxY)
        )
        path.addLine(to: CGPoint(x: rect.maxX - ear, y: rect.minY + ear))
        path.addQuadCurve(
            to: CGPoint(x: rect.maxX, y: rect.minY),
            control: CGPoint(x: rect.maxX - ear, y: rect.minY)
        )
        path.closeSubpath()
        return path
    }
}
