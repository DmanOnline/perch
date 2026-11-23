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
        NSApp.activate()
        window.makeKeyAndOrderFront(nil)
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
        window.center()
        window.setFrameAutosaveName("PerchSettings")
        return window
    }
}
