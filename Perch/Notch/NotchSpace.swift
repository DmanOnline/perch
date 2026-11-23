import AppKit

/// A private window-server space that sits above every desktop.
///
/// A normal window, even one on all Spaces, slides along with the desktop
/// when you swipe between Spaces, so the black notch shape would sweep across
/// the menu bar. Windows in their own space at the highest level stay put
/// through every Space transition, and over full-screen apps.
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
        CGSSpaceSetAbsoluteLevel(connection, space, Int(Int32.max))
        CGSShowSpaces(connection, [space] as NSArray)
    }

    func add(_ window: NSWindow) {
        let number = window.windowNumber
        guard number > 0, windows.insert(number).inserted else { return }
        CGSAddWindowsToSpaces(connection, [number] as NSArray, [space] as NSArray)
    }

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
