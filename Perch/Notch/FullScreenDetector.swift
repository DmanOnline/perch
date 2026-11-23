import AppKit

/// Decides when Perch steps aside: only while a video plays in full screen.
/// Other full-screen apps (Claude, Xcode, a browser with a document) keep the
/// notch. Reads only window bounds and owners, which needs no Screen
/// Recording permission.
nonisolated enum FullScreenDetector {
    struct Window: Equatable, Sendable {
        /// In CoreGraphics coordinates: origin at the top left of the main screen.
        var bounds: CGRect
        var layer: Int
        var ownerPID: pid_t
    }

    /// Apps that only ever play video; full screen in these always means a video.
    static let videoPlayers: Set<String> = [
        "com.apple.QuickTimePlayerX",
        "com.apple.TV",
        "com.colliderli.iina",
        "org.videolan.vlc",
        "com.firecore.infuse",
    ]

    /// Apps whose Now Playing is audio; full screen in these is not a video.
    static let audioPlayers: Set<String> = [
        "com.spotify.client",
        "com.apple.Music",
        "com.apple.podcasts",
    ]

    /// Full-screen windows on a notched Mac start below the notch, so the top
    /// of the screen may stay uncovered by this much.
    static let topAllowance: CGFloat = 40

    /// For each screen that a normal window of another app covers from the top
    /// (or just under the notch) to the bottom, edge to edge, the process that
    /// owns that window.
    static func coveringOwners(windows: [Window], screens: [CGDirectDisplayID: CGRect], ownPID: pid_t) -> [CGDirectDisplayID: pid_t] {
        var owners: [CGDirectDisplayID: pid_t] = [:]
        // The window list runs front to back; the first match per screen is on top.
        for window in windows where window.layer == 0 && window.ownerPID != ownPID {
            for (id, frame) in screens where owners[id] == nil {
                let mustCover = CGRect(x: frame.minX, y: frame.minY + topAllowance,
                                       width: frame.width, height: frame.height - topAllowance)
                if window.bounds.insetBy(dx: -1, dy: -1).contains(mustCover.insetBy(dx: 2, dy: 2)) {
                    owners[id] = window.ownerPID
                }
            }
        }
        return owners
    }

    /// True when a full-screen window of `owner` means someone is watching video:
    /// it is a video player, or it is the app whose media is playing right now
    /// (`mediaSource` is only set while something plays: a browser in full
    /// screen with a paused tab somewhere is just a browser).
    static func isWatchingVideo(owner: String?, mediaSource: String?) -> Bool {
        guard let owner else { return false }
        if videoPlayers.contains(owner) { return true }
        if audioPlayers.contains(owner) { return false }
        return owner == mediaSource
    }

    /// For each screen covered by another app's full-screen window: that app.
    @MainActor
    static func coveringApps() -> [CGDirectDisplayID: (pid: pid_t, bundleID: String?)] {
        let options: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]
        guard let info = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] else { return [:] }
        let windows = info.compactMap { entry -> Window? in
            guard let boundsDict = entry[kCGWindowBounds as String] as? NSDictionary,
                  let bounds = CGRect(dictionaryRepresentation: boundsDict),
                  let layer = entry[kCGWindowLayer as String] as? Int,
                  let pid = entry[kCGWindowOwnerPID as String] as? pid_t
            else { return nil }
            return Window(bounds: bounds, layer: layer, ownerPID: pid)
        }
        var screens: [CGDirectDisplayID: CGRect] = [:]
        for screen in NSScreen.screens {
            guard let id = screen.displayID else { continue }
            screens[id] = CGDisplayBounds(id)
        }
        let owners = coveringOwners(windows: windows, screens: screens, ownPID: ProcessInfo.processInfo.processIdentifier)
        return owners.mapValues { pid in (pid, NSRunningApplication(processIdentifier: pid)?.bundleIdentifier) }
    }
}
