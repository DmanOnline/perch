import Foundation
import Observation

/// Whether the screen is locked, from the distributed notifications the
/// login window posts. On the lock screen Perch shows only what is safe for
/// anyone at the Mac to see: music, timer, batteries. No files, no camera, no
/// settings.
@Observable
final class LockState {
    static let shared = LockState()

    /// Modules that may show on the lock screen.
    static let allowedModules: Set<String> = ["music", "timer", "battery", "devices", "hud", "privacy"]

    private(set) var isLocked = false
    @ObservationIgnored private var observers: [NSObjectProtocol] = []

    func start() {
        let center = DistributedNotificationCenter.default()
        observers = [
            center.addObserver(forName: Notification.Name("com.apple.screenIsLocked"), object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.isLocked = true }
            },
            center.addObserver(forName: Notification.Name("com.apple.screenIsUnlocked"), object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.isLocked = false }
            },
        ]
        #if DEBUG
        // Try the lock-screen layout without locking: post
        // "com.itcompleet.perch.debug.lock" / ".unlock".
        observers += [
            center.addObserver(forName: Notification.Name("com.itcompleet.perch.debug.lock"), object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.isLocked = true }
            },
            center.addObserver(forName: Notification.Name("com.itcompleet.perch.debug.unlock"), object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.isLocked = false }
            },
        ]
        #endif
    }
}
