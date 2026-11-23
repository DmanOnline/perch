import SwiftUI

nonisolated enum NotchState: Equatable, Sendable {
    case closed
    case compact
    case expanded
}

/// Sizes and motion of the notch. One place, so window, hit testing and
/// drawing can never disagree.
nonisolated enum NotchMetrics {
    static let compactWingWidth: CGFloat = 80
    static let expandedSize = CGSize(width: 580, height: 190)
    static let hoverPadding: CGFloat = 10
    /// Room under the body for the open-state shadow.
    static let shadowPadding: CGFloat = 24
    /// How far the closed notch grows while the pointer rests on it.
    static let peekGrowth = CGSize(width: 10, height: 3)

    static let hoverExit: Duration = .milliseconds(160)

    /// Opening overshoots a touch; closing settles without bounce.
    static let openAnimation = Animation.spring(response: 0.42, dampingFraction: 0.8, blendDuration: 0)
    static let closeAnimation = Animation.spring(response: 0.45, dampingFraction: 1.0, blendDuration: 0)

    /// Width of the flared "ears" at the top corners.
    static func earRadius(for state: NotchState) -> CGFloat {
        state == .expanded ? 19 : 6
    }

    static func bottomRadius(for state: NotchState) -> CGFloat {
        state == .expanded ? 24 : 14
    }

    /// Size of the black body, ears excluded.
    static func bodySize(for state: NotchState, notch: CGSize, peeking: Bool = false) -> CGSize {
        switch state {
        case .closed:
            peeking ? CGSize(width: notch.width + peekGrowth.width, height: notch.height + peekGrowth.height) : notch
        case .compact:
            CGSize(width: notch.width + 2 * compactWingWidth, height: notch.height + (peeking ? peekGrowth.height : 0))
        case .expanded:
            CGSize(width: max(expandedSize.width, notch.width + 2 * compactWingWidth), height: expandedSize.height)
        }
    }

    /// Size of the panel: the expanded body with its ears, plus room for the shadow.
    static func panelSize(notch: CGSize) -> CGSize {
        let body = bodySize(for: .expanded, notch: notch)
        return CGSize(
            width: body.width + 2 * earRadius(for: .expanded) + 2 * shadowPadding,
            height: body.height + shadowPadding
        )
    }
}
