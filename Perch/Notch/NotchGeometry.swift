import AppKit

/// Where the notch is on a screen, in that screen's coordinates.
///
/// Screens without a hardware notch get a virtual one of the same proportions,
/// sitting in the menu bar, so Perch behaves the same everywhere.
nonisolated struct NotchGeometry: Equatable, Sendable {
    static let virtualNotchWidth: CGFloat = 190

    let screenFrame: CGRect
    let notchSize: CGSize
    let hasHardwareNotch: Bool

    static func make(
        screenFrame: CGRect,
        safeAreaTop: CGFloat,
        auxiliaryTopLeft: CGRect?,
        auxiliaryTopRight: CGRect?,
        menuBarHeight: CGFloat
    ) -> NotchGeometry {
        if safeAreaTop > 0, let left = auxiliaryTopLeft, let right = auxiliaryTopRight {
            let width = screenFrame.width - left.width - right.width
            if width > 0 {
                return NotchGeometry(
                    screenFrame: screenFrame,
                    notchSize: CGSize(width: width, height: safeAreaTop),
                    hasHardwareNotch: true
                )
            }
        }
        let height = max(menuBarHeight, 24)
        return NotchGeometry(
            screenFrame: screenFrame,
            notchSize: CGSize(width: virtualNotchWidth, height: height),
            hasHardwareNotch: false
        )
    }

    /// Rect of a notch-shaped body of `size`, centred under the top edge, in screen coordinates.
    func bodyRect(size: CGSize) -> CGRect {
        CGRect(
            x: screenFrame.midX - size.width / 2,
            y: screenFrame.maxY - size.height,
            width: size.width,
            height: size.height
        )
    }
}

extension NSScreen {
    var displayID: CGDirectDisplayID? {
        deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID
    }

    var notchGeometry: NotchGeometry {
        NotchGeometry.make(
            screenFrame: frame,
            safeAreaTop: safeAreaInsets.top,
            auxiliaryTopLeft: auxiliaryTopLeftArea,
            auxiliaryTopRight: auxiliaryTopRightArea,
            menuBarHeight: frame.maxY - visibleFrame.maxY
        )
    }
}
