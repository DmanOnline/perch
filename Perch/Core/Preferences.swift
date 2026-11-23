import Foundation
import Observation

nonisolated enum DisplayMode: String, CaseIterable, Sendable {
    /// Every screen with a hardware notch; the main screen when none has one.
    case notchedScreens
    case mainScreen
    case allScreens
}

/// User settings, stored in `UserDefaults`. Observable, so the notch and the
/// modules follow a change the moment it is made.
@Observable
final class Preferences {
    static let shared = Preferences()

    nonisolated enum Key {
        static let openOnHover = "openOnHover"
        static let hoverDelay = "hoverDelay"
        static let haptics = "haptics"
        static let hapticStrength = "hapticStrength"
        static let displayMode = "displayMode"
        static let disabledModules = "disabledModules"
        static let musicLinger = "music.linger"
        static let batteryShowOnPlugIn = "battery.showOnPlugIn"
        static let batteryLowThreshold = "battery.lowThreshold"
    }

    nonisolated enum Default {
        static let hoverDelay = 0.3
        static let musicLinger = 6.0
        static let batteryLowThreshold = 10
    }

    @ObservationIgnored private let defaults: UserDefaults

    /// Open when the pointer rests on the notch. Off: open on click only.
    var openOnHover: Bool { didSet { defaults.set(openOnHover, forKey: Key.openOnHover) } }
    /// Seconds the pointer must rest before the notch opens.
    var hoverDelay: Double { didSet { defaults.set(hoverDelay, forKey: Key.hoverDelay) } }
    var hapticStrength: HapticStrength { didSet { defaults.set(hapticStrength.rawValue, forKey: Key.hapticStrength) } }
    var displayMode: DisplayMode { didSet { defaults.set(displayMode.rawValue, forKey: Key.displayMode) } }
    private(set) var disabledModules: Set<String> {
        didSet { defaults.set(disabledModules.sorted(), forKey: Key.disabledModules) }
    }
    /// Seconds music keeps the notch after a pause; 0 lets go at once.
    var musicLinger: Double { didSet { defaults.set(musicLinger, forKey: Key.musicLinger) } }
    var batteryShowOnPlugIn: Bool { didSet { defaults.set(batteryShowOnPlugIn, forKey: Key.batteryShowOnPlugIn) } }
    var batteryLowThreshold: Int { didSet { defaults.set(batteryLowThreshold, forKey: Key.batteryLowThreshold) } }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        openOnHover = defaults.object(forKey: Key.openOnHover) as? Bool ?? true
        hoverDelay = defaults.object(forKey: Key.hoverDelay) as? Double ?? Default.hoverDelay
        if let stored = defaults.string(forKey: Key.hapticStrength).flatMap(HapticStrength.init(rawValue:)) {
            hapticStrength = stored
        } else {
            // 0.1 builds stored an on/off switch.
            hapticStrength = defaults.object(forKey: Key.haptics) as? Bool == false ? .off : .strong
        }
        displayMode = defaults.string(forKey: Key.displayMode).flatMap(DisplayMode.init(rawValue:)) ?? .notchedScreens
        disabledModules = Set(defaults.stringArray(forKey: Key.disabledModules) ?? [])
        musicLinger = defaults.object(forKey: Key.musicLinger) as? Double ?? Default.musicLinger
        batteryShowOnPlugIn = defaults.object(forKey: Key.batteryShowOnPlugIn) as? Bool ?? true
        batteryLowThreshold = defaults.object(forKey: Key.batteryLowThreshold) as? Int ?? Default.batteryLowThreshold
    }

    func isEnabled(_ moduleID: String) -> Bool {
        !disabledModules.contains(moduleID)
    }

    func setEnabled(_ enabled: Bool, for moduleID: String) {
        if enabled { disabledModules.remove(moduleID) } else { disabledModules.insert(moduleID) }
    }
}
