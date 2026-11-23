import AppKit

/// Keeps a notch on the right screens and keeps it alive.
///
/// The notch must survive sleep, display changes and Space switches. Instead of
/// trusting the window server to keep the panel where it was, every one of those
/// events re-reads the screens and re-pins each panel.
final class NotchController {
    private let host: ModuleHost
    private let preferences: Preferences
    /// Bundle ID of the app playing media now, if any.
    private let mediaSource: () -> String?
    private var windows: [CGDirectDisplayID: NotchWindowController] = [:]
    private var observers: [NSObjectProtocol] = []
    private var mouseMonitors: [Any] = []

    init(host: ModuleHost, preferences: Preferences = .shared, mediaSource: @escaping () -> String? = { nil }) {
        self.host = host
        self.preferences = preferences
        self.mediaSource = mediaSource
    }

    func start() {
        rebuild()
        observe()
        followDisplayMode()
        followFullScreenSetting()
        monitorPointer()
    }

    // MARK: Full screen

    private var fullScreenCheck: Task<Void, Never>?

    /// Hides the notch on screens where a video plays in full screen. Checked
    /// when the Space, the frontmost app or the media source changes, and once
    /// more after a Space animation has settled, since windows move during it.
    private func updateFullScreen() {
        fullScreenCheck?.cancel()
        applyFullScreen()
        fullScreenCheck = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(700))
            guard !Task.isCancelled else { return }
            self?.applyFullScreen()
        }
    }

    /// Screens hidden for a video, and the app whose full-screen window it was.
    /// Pausing the film keeps the notch away until that window leaves.
    private var watching: [CGDirectDisplayID: pid_t] = [:]

    private func applyFullScreen() {
        let apps = preferences.hideInFullScreen ? FullScreenDetector.coveringApps() : [:]
        let source = mediaSource()
        var next: [CGDirectDisplayID: pid_t] = [:]
        for (id, app) in apps where watching[id] == app.pid
            || FullScreenDetector.isWatchingVideo(owner: app.bundleID, mediaSource: source) {
            next[id] = app.pid
        }
        watching = next
        // Volume and brightness still come through, as they do over a video on iPhone.
        let showsLevel = host.current?.moduleID == "hud"
        for (id, window) in windows {
            window.setHidden(next[id] != nil && !showsLevel)
        }
    }

    private func followFullScreenSetting() {
        withObservationTracking {
            _ = preferences.hideInFullScreen
            _ = mediaSource()
            _ = host.current?.moduleID
        } onChange: { [weak self] in
            Task { @MainActor in
                self?.applyFullScreen()
                self?.followFullScreenSetting()
            }
        }
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
        updateFullScreen()
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
            workspace.addObserver(forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.updateFullScreen() }
            },
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
