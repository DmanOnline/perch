import Foundation
import Observation

/// State of the notch on one screen.
@Observable
final class NotchModel {
    let host: ModuleHost
    var geometry: NotchGeometry
    var isHovering = false
    /// Pointer rests on the closed notch but has not opened it yet.
    var isPeeking = false
    var selectedModuleID: String?
    /// Set by the window controller; called when the user clicks the closed notch.
    @ObservationIgnored var onRequestOpen: (() -> Void)?

    init(host: ModuleHost, geometry: NotchGeometry) {
        self.host = host
        self.geometry = geometry
    }

    var state: NotchState {
        if isHovering { return .expanded }
        return host.current == nil ? .closed : .compact
    }

    var bodySize: CGSize {
        NotchMetrics.bodySize(for: state, notch: geometry.notchSize, peeking: isPeeking)
    }

    /// Module shown when expanded: the one that currently has the notch,
    /// otherwise the tab the user picked, otherwise the first.
    var expandedModule: (any PerchModule)? {
        if let selectedModuleID, let module = host.module(id: selectedModuleID) { return tab(of: module) }
        if let current = host.current, let module = host.module(id: current.moduleID) { return tab(of: module) }
        return host.enabledModules.first
    }

    /// Modules that have a tab of their own, in order.
    var tabs: [any PerchModule] {
        host.enabledModules.filter { $0.tabID == $0.id }
    }

    private func tab(of module: any PerchModule) -> any PerchModule {
        host.module(id: module.tabID) ?? module
    }

    /// Area of the screen where the pointer keeps (or makes) the notch open.
    var hoverRect: CGRect {
        let ear = NotchMetrics.earRadius(for: state)
        let size = CGSize(width: bodySize.width + 2 * ear, height: bodySize.height)
        return geometry.bodyRect(size: size).insetBy(dx: -NotchMetrics.hoverPadding, dy: -NotchMetrics.hoverPadding)
    }
}
