import AppKit
import SwiftUI

/// The settings window. Perch has no Dock icon or menu bar, so this is opened
/// from the gear in the notch, or by opening the app again from Finder.
final class SettingsWindowController {
    static let shared = SettingsWindowController()

    var host: ModuleHost?
    private var window: NSWindow?

    func show() {
        let window = self.window ?? makeWindow()
        self.window = window
        let wasVisible = window.isVisible
        if !wasVisible { window.layoutIfNeeded() }
        NSApp.activate()
        window.makeKeyAndOrderFront(nil)
        // Placed after it has laid out: only then does it know its size.
        if !wasVisible { placeUnderNotch(window) }
    }

    /// Centred just below the notch on the screen with the pointer: it opens
    /// from the notch, so it appears where you were looking.
    private func placeUnderNotch(_ window: NSWindow) {
        let pointer = NSEvent.mouseLocation
        guard let screen = NSScreen.screens.first(where: { $0.frame.contains(pointer) }) ?? NSScreen.main else {
            window.center()
            return
        }
        let visible = screen.visibleFrame
        let size = window.frame.size
        window.setFrameOrigin(NSPoint(x: visible.midX - size.width / 2,
                                      y: max(visible.minY, visible.maxY - size.height - 24)))
    }

    private func makeWindow() -> NSWindow {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: SettingsView.width, height: 560),
            styleMask: [.titled, .closable, .miniaturizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.title = "Perch Settings"
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.isMovableByWindowBackground = true
        window.isReleasedWhenClosed = false
        window.appearance = NSAppearance(named: .darkAqua)
        window.backgroundColor = NSColor(SettingsStyle.background)
        let hosting = NSHostingController(rootView: SettingsView(host: host))
        hosting.sizingOptions = [.preferredContentSize]
        window.contentViewController = hosting
        return window
    }
}
