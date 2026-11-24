import AppKit

/// A private window-server space that sits above every desktop.
///
/// A normal window, even one on all Spaces, slides along with the desktop
/// when you swipe between Spaces, so the black notch shape would sweep across
/// the menu bar. Windows in their own space at the highest level stay put
/// through every Space transition, and over full-screen apps.
///
/// The space sits at the level of Notification Center on the lock screen, so
/// the notch also shows over the lock screen (together with the panel's
/// `canBecomeVisibleWithoutLogin`). Level and calls follow Lakr233's
/// SkyLightWindow (MIT), which boring.notch uses for the same.
///
/// Uses the SkyLight (CoreGraphics Services) space calls that the window
/// server exposes privately; boring.notch, Parrot and SkyLightWindow rely on
/// the same calls. If Apple ever removes them, the app fails to launch, so
/// this is the place to look first after a macOS update.
final class NotchSpace {
    static let shared = NotchSpace()

    private let connection = _CGSDefaultConnection()
    private let space: CGSSpaceID
    private var windows: Set<Int> = []

    private init() {
        space = CGSSpaceCreate(connection, 1, nil)
        // kSLSSpaceAbsoluteLevelNotificationCenterAtScreenLock: above every
        // desktop and the lock screen, below boot progress and VoiceOver.
        CGSSpaceSetAbsoluteLevel(connection, space, 400)
        CGSShowSpaces(connection, [space] as NSArray)
    }

    func add(_ window: NSWindow) {
        let number = window.windowNumber
        guard number > 0, windows.insert(number).inserted else { return }
        // Move, not just add: a window still in its old space is drawn with that
        // space, which the lock screen covers.
        if let move = Self.addAndRemoveFromOtherSpaces {
            _ = move(Int32(connection), Int32(truncatingIfNeeded: space), [number] as CFArray, 7)
        } else {
            CGSAddWindowsToSpaces(connection, [number] as NSArray, [space] as NSArray)
        }
    }

    private typealias AddAndRemove = @convention(c) (Int32, Int32, CFArray, Int32) -> Int32
    private static let addAndRemoveFromOtherSpaces: AddAndRemove? = {
        guard let skyLight = dlopen("/System/Library/PrivateFrameworks/SkyLight.framework/Versions/A/SkyLight", RTLD_NOW),
              let symbol = dlsym(skyLight, "SLSSpaceAddWindowsAndRemoveFromSpaces") else { return nil }
        return unsafeBitCast(symbol, to: AddAndRemove.self)
    }()

    func remove(_ window: NSWindow) {
        let number = window.windowNumber
        guard windows.remove(number) != nil else { return }
        CGSRemoveWindowsFromSpaces(connection, [number] as NSArray, [space] as NSArray)
    }
}

private typealias CGSConnectionID = Int32
private typealias CGSSpaceID = UInt64

@_silgen_name("_CGSDefaultConnection")
private func _CGSDefaultConnection() -> CGSConnectionID

@_silgen_name("CGSSpaceCreate")
private func CGSSpaceCreate(_ connection: CGSConnectionID, _ flag: Int, _ options: NSDictionary?) -> CGSSpaceID

@_silgen_name("CGSSpaceSetAbsoluteLevel")
private func CGSSpaceSetAbsoluteLevel(_ connection: CGSConnectionID, _ space: CGSSpaceID, _ level: Int)

@_silgen_name("CGSShowSpaces")
private func CGSShowSpaces(_ connection: CGSConnectionID, _ spaces: NSArray)

@_silgen_name("CGSAddWindowsToSpaces")
private func CGSAddWindowsToSpaces(_ connection: CGSConnectionID, _ windows: NSArray, _ spaces: NSArray)

@_silgen_name("CGSRemoveWindowsFromSpaces")
private func CGSRemoveWindowsFromSpaces(_ connection: CGSConnectionID, _ windows: NSArray, _ spaces: NSArray)
