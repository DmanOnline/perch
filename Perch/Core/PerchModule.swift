import SwiftUI

/// How strongly an activity asks for the notch.
nonisolated enum ActivityPriority: Int, Comparable, Sendable {
    case background = 0
    case info = 1
    case attention = 2
    case urgent = 3

    static func < (lhs: Self, rhs: Self) -> Bool { lhs.rawValue < rhs.rawValue }
}

/// Something a module wants to show in the collapsed notch.
nonisolated struct Activity: Identifiable, Equatable, Sendable {
    let id: String
    let moduleID: String
    var priority: ActivityPriority
    var startedAt: Date
    var expiresAt: Date?

    init(id: String, moduleID: String, priority: ActivityPriority, startedAt: Date = .now, expiresAt: Date? = nil) {
        self.id = id
        self.moduleID = moduleID
        self.priority = priority
        self.startedAt = startedAt
        self.expiresAt = expiresAt
    }

    func isExpired(at date: Date) -> Bool {
        guard let expiresAt else { return false }
        return expiresAt <= date
    }
}

/// The contract every feature of Perch implements, built-in or not.
///
/// A module owns its state and views. It never touches the window: it publishes
/// an `activity` and the `Arbiter` decides whether that activity gets the notch.
protocol PerchModule: AnyObject {
    var id: String { get }
    var title: String { get }
    var symbol: String { get }
    /// One line for the settings: what this module shows.
    var summary: String { get }
    var activity: Activity? { get }

    func start()
    func stop()

    func compactLeading() -> AnyView
    func compactTrailing() -> AnyView
    func expanded() -> AnyView
    /// Options shown under the module in the settings, if any.
    func settings() -> AnyView?
    /// Drawn across the whole compact notch, above the wings and clipped to the
    /// notch shape, for effects that span both sides.
    func compactOverlay() -> AnyView?
    /// What to keep in the notch when nothing is happening, if the user chose
    /// this module for the sneak peek. Nil when there is nothing worth showing.
    var restingActivity: Activity? { get }
    /// The tab this module lives in when the notch is open. Its own `id` gives
    /// it a tab; another module's id folds it into that tab instead.
    var tabID: String { get }
}

extension PerchModule {
    func settings() -> AnyView? { nil }
    func compactOverlay() -> AnyView? { nil }
    var restingActivity: Activity? { nil }
    var tabID: String { id }
}
