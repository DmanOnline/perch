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
    var activity: Activity? { get }

    func start()
    func stop()

    func compactLeading() -> AnyView
    func compactTrailing() -> AnyView
    func expanded() -> AnyView
}
