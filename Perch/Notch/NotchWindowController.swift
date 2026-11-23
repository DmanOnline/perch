import AppKit
import SwiftUI

/// One notch panel on one screen.
final class NotchWindowController {
    let model: NotchModel
    private let panel: NotchPanel
    private let preferences = Preferences.shared
    private var openTask: Task<Void, Never>?
    private var closeTask: Task<Void, Never>?
    /// Stepped aside for a full-screen app on this screen.
    private(set) var isHidden = false

    init(host: ModuleHost, screen: NSScreen) {
        model = NotchModel(host: host, geometry: screen.notchGeometry)
        panel = NotchPanel(contentRect: .zero)
        let hosting = NotchHostingView(rootView: NotchView(model: model))
        hosting.sizingOptions = []
        panel.contentView = hosting
        model.onRequestOpen = { [weak self] in self?.open() }
        place(on: screen)
    }

    /// Re-reads the screen and pins the panel to its top centre. Safe to call
    /// as often as needed: after wake, display changes and Space switches.
    func place(on screen: NSScreen) {
        model.geometry = screen.notchGeometry
        let size = NotchMetrics.panelSize(notch: model.geometry.notchSize)
        panel.setFrame(model.geometry.bodyRect(size: size), display: true)
        panel.orderFrontRegardless()
        NotchSpace.shared.add(panel)
    }

    func close() {
        openTask?.cancel()
        closeTask?.cancel()
        NotchSpace.shared.remove(panel)
        panel.orderOut(nil)
    }

    /// Rest on the notch: it grows a little and ticks the trackpad, then opens
    /// after the hover delay (unless set to open on click). A click opens at once.
    /// Leaving closes after `hoverExit`.
    func pointerMoved(to location: NSPoint) {
        guard !isHidden else { return }
        let inside = model.hoverRect.contains(location)
        if inside {
            closeTask?.cancel()
            closeTask = nil
            guard !model.isHovering, !model.isPeeking else { return }
            model.isPeeking = true
            panel.ignoresMouseEvents = false
            Haptics.play(.peek)
            guard preferences.openOnHover else { return }
            let dwell = Duration.milliseconds(Int(preferences.hoverDelay * 1000))
            openTask = Task { [weak self] in
                try? await Task.sleep(for: dwell)
                guard !Task.isCancelled else { return }
                self?.open()
            }
        } else {
            openTask?.cancel()
            openTask = nil
            if model.isPeeking, !model.isHovering {
                model.isPeeking = false
                panel.ignoresMouseEvents = true
            }
            guard model.isHovering, closeTask == nil else { return }
            closeTask = Task { [weak self] in
                try? await Task.sleep(for: NotchMetrics.hoverExit)
                guard !Task.isCancelled else { return }
                self?.collapse()
            }
        }
    }

    /// Fades the notch out while a full-screen app has this screen, and back
    /// in afterwards. The panel stays in place, so nothing has to be rebuilt.
    func setHidden(_ hidden: Bool) {
        guard hidden != isHidden else { return }
        isHidden = hidden
        if hidden {
            openTask?.cancel()
            collapse()
        }
        NSAnimationContext.runAnimationGroup { context in
            context.duration = hidden ? 0.2 : 0.35
            panel.animator().alphaValue = hidden ? 0 : 1
        }
    }

    private func open() {
        openTask?.cancel()
        openTask = nil
        guard !model.isHovering else { return }
        Haptics.play(.open)
        model.isHovering = true
        model.isPeeking = false
        panel.ignoresMouseEvents = false
    }

    private func collapse() {
        closeTask = nil
        if model.isHovering { Haptics.play(.close) }
        model.isHovering = false
        model.isPeeking = false
        model.selectedModuleID = nil
        panel.ignoresMouseEvents = true
    }
}

/// Takes the first click even while the panel is not key, so a button in the
/// notch never needs a second click.
/// Not generic on purpose: a generic subclass of NSHostingView crashes the
/// Swift 6.3 optimizer (Xcode 26.6) in Release builds.
private final class NotchHostingView: NSHostingView<NotchView> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}
