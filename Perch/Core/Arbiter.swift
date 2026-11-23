import Foundation

/// Decides which activity owns the collapsed notch.
///
/// Highest priority wins; between equal priorities the most recent one wins,
/// so a fresh event is never hidden behind an older one of the same weight.
nonisolated enum Arbiter {
    static func select(_ activities: [Activity], now: Date) -> Activity? {
        activities
            .filter { !$0.isExpired(at: now) }
            .max { lhs, rhs in
                if lhs.priority != rhs.priority { return lhs.priority < rhs.priority }
                return lhs.startedAt < rhs.startedAt
            }
    }
}
