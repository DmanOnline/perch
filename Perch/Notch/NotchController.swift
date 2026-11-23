import AppKit

/// Keeps a notch on the right screens and keeps it alive.
///
/// The notch must survive sleep, display changes and Space switches. Instead of
/// trusting the window server to keep the panel where it was, every one of those
/// events re-reads the screens and re-pins each panel.
final class NotchController {
    private let host: ModuleHost
    private let preferences: Preferences
    private var windows: [CGDirectDisplayID: NotchWindowController] = [:]
    private var observers: [NSObjectProtocol] = []
    private var mouseMonitors: [Any] = []

    init(host: ModuleHost, preferences: Preferences = .shared) {
        self.host = host
        self.preferences = preferences
    }

    func start() {
        rebuild()
        observe()
        followDisplayMode()
        monitorPointer()
    }

    /// Screens that get a notch, per the display setting. "Screens with a notch"
    /// falls back to the main screen when none has one.
    private func targetScreens() -> [NSScreen] {
        switch preferences.displayMode {
        case .allScreens:
            return NSScreen.screens
        case .mainScreen:
            return (NSScreen.screens.first).map { [$0] } ?? []
        case .notchedScreens:
            let notched = NSScreen.screens.filter { $0.notchGeometry.hasHardwareNotch }
            if !notched.isEmpty { return notched }
            return NSScreen.screens.first.map { [$0] } ?? []
        }
    }

    private func followDisplayMode() {
        withObservationTracking {
            _ = preferences.displayMode
        } onChange: { [weak self] in
            Task { @MainActor in
                self?.rebuild()
                self?.followDisplayMode()
            }
        }
    }

    private func rebuild() {
        var next: [CGDirectDisplayID: NotchWindowController] = [:]
        for screen in targetScreens() {
            guard let id = screen.displayID else { continue }
            if let existing = windows[id] {
                existing.place(on: screen)
                next[id] = existing
            } else {
                next[id] = NotchWindowController(host: host, screen: screen)
            }
        }
        for (id, window) in windows where next[id] == nil {
            window.close()
        }
        windows = next
    }

    private func observe() {
        let center = NotificationCenter.default
        let workspace = NSWorkspace.shared.notificationCenter
        let refresh: @Sendable (Notification) -> Void = { [weak self] _ in
            MainActor.assumeIsolated { self?.rebuild() }
        }
        observers = [
            center.addObserver(forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main, using: refresh),
            workspace.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main, using: refresh),
            workspace.addObserver(forName: NSWorkspace.screensDidWakeNotification, object: nil, queue: .main, using: refresh),
            workspace.addObserver(forName: NSWorkspace.activeSpaceDidChangeNotification, object: nil, queue: .main, using: refresh),
            workspace.addObserver(forName: NSWorkspace.sessionDidBecomeActiveNotification, object: nil, queue: .main, using: refresh),
        ]
    }

    private func monitorPointer() {
        let mask: NSEvent.EventTypeMask = [.mouseMoved, .leftMouseDragged]
        if let global = NSEvent.addGlobalMonitorForEvents(matching: mask, handler: { [weak self] _ in
            MainActor.assumeIsolated { self?.pointerMoved() }
        }) {
            mouseMonitors.append(global)
        }
        if let local = NSEvent.addLocalMonitorForEvents(matching: mask, handler: { [weak self] event in
            MainActor.assumeIsolated { self?.pointerMoved() }
            return event
        }) {
            mouseMonitors.append(local)
        }
    }

    private func pointerMoved() {
        let location = NSEvent.mouseLocation
        for window in windows.values {
            window.pointerMoved(to: location)
        }
    }
}
