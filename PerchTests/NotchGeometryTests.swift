import CoreGraphics
import Testing
@testable import Perch

struct NotchGeometryTests {
    /// 14" MacBook Pro in its default scaled resolution.
    private let screen = CGRect(x: 0, y: 0, width: 1512, height: 982)

    @Test func hardwareNotchIsTheGapBetweenAuxiliaryAreas() {
        let geometry = NotchGeometry.make(
            screenFrame: screen,
            safeAreaTop: 32,
            auxiliaryTopLeft: CGRect(x: 0, y: 950, width: 663, height: 32),
            auxiliaryTopRight: CGRect(x: 849, y: 950, width: 663, height: 32),
            menuBarHeight: 32
        )
        #expect(geometry.hasHardwareNotch)
        #expect(geometry.notchSize == CGSize(width: 186, height: 32))
    }

    @Test func screenWithoutNotchGetsVirtualNotch() {
        let geometry = NotchGeometry.make(
            screenFrame: CGRect(x: 1512, y: 0, width: 2560, height: 1440),
            safeAreaTop: 0,
            auxiliaryTopLeft: nil,
            auxiliaryTopRight: nil,
            menuBarHeight: 25
        )
        #expect(!geometry.hasHardwareNotch)
        #expect(geometry.notchSize == CGSize(width: NotchGeometry.virtualNotchWidth, height: 25))
    }

    @Test func bodyIsCentredUnderTopEdge() {
        let geometry = NotchGeometry(screenFrame: screen, notchSize: CGSize(width: 186, height: 32), hasHardwareNotch: true)
        let rect = geometry.bodyRect(size: CGSize(width: 200, height: 40))
        #expect(rect.midX == screen.midX)
        #expect(rect.maxY == screen.maxY)
    }

    @Test func panelFitsExpandedBodyWithEarsAndShadow() {
        let notch = CGSize(width: 186, height: 32)
        let panel = NotchMetrics.panelSize(notch: notch)
        let expanded = NotchMetrics.bodySize(for: .expanded, notch: notch)
        #expect(panel.width >= expanded.width + 2 * NotchMetrics.earRadius(for: .expanded) + 2 * NotchMetrics.shadowPadding)
        #expect(panel.height >= NotchMetrics.maxExpandedHeight + NotchMetrics.shadowPadding)
        #expect(panel.height >= expanded.height + NotchMetrics.shadowPadding)
    }

    @Test func closedBodyMatchesNotchExactly() {
        let notch = CGSize(width: 186, height: 32)
        #expect(NotchMetrics.bodySize(for: .closed, notch: notch) == notch)
    }

    @Test func peekingGrowsClosedNotchSlightly() {
        let notch = CGSize(width: 186, height: 32)
        let peek = NotchMetrics.bodySize(for: .closed, notch: notch, peeking: true)
        #expect(peek.width > notch.width && peek.width <= notch.width + 12)
        #expect(peek.height > notch.height && peek.height <= notch.height + 4)
    }
}
