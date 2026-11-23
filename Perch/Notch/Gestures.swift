import AppKit

/// A two-finger swipe on the trackpad, in the direction the fingers moved,
/// whatever the natural-scrolling setting.
nonisolated enum Swipe: Equatable, Sendable {
    case up, down, left, right
}

/// Turns the scroll events of one two-finger movement into at most one swipe:
/// it adds up the movement and answers once the fingers have clearly gone one
/// way. A new movement (scroll phase "began") starts it over.
nonisolated struct SwipeTracker {
    /// How far the fingers must travel, in scroll points, before it counts.
    static let threshold: CGFloat = 36
    /// How much more one axis must move than the other.
    static let dominance: CGFloat = 1.6

    private var dx: CGFloat = 0
    private var dy: CGFloat = 0
    private var fired = false

    mutating func reset() {
        dx = 0
        dy = 0
        fired = false
    }

    /// Feeds one event's finger movement (positive x is right, positive y is
    /// down). Returns the swipe the first time the movement is clear enough.
    mutating func add(dx: CGFloat, dy: CGFloat) -> Swipe? {
        guard !fired else { return nil }
        self.dx += dx
        self.dy += dy
        let ax = abs(self.dx), ay = abs(self.dy)
        if ay >= Self.threshold, ay >= ax * Self.dominance {
            fired = true
            return self.dy > 0 ? .down : .up
        }
        if ax >= Self.threshold, ax >= ay * Self.dominance {
            fired = true
            return self.dx > 0 ? .right : .left
        }
        return nil
    }

    /// The fingers' own movement for an event: scroll deltas follow the
    /// content, which natural scrolling flips relative to the fingers.
    /// Horizontally the content moves against the fingers, so x is negated
    /// (checked on a trackpad with natural scrolling on).
    static func fingerMovement(of event: NSEvent) -> (dx: CGFloat, dy: CGFloat) {
        let sign: CGFloat = event.isDirectionInvertedFromDevice ? 1 : -1
        return (-event.scrollingDeltaX * sign, event.scrollingDeltaY * sign)
    }
}

/// The parts of a scroll event a gesture needs, copied out so they can cross
/// from the event monitor to the main actor.
nonisolated struct ScrollInput: Sendable {
    var dx: CGFloat
    var dy: CGFloat
    var began: Bool
    var ended: Bool
    var isMomentum: Bool
    /// Trackpad or Magic Mouse; a wheel mouse scrolls in coarse steps.
    var isPrecise: Bool

    init(_ event: NSEvent) {
        (dx, dy) = SwipeTracker.fingerMovement(of: event)
        began = event.phase.contains(.began) || event.phase.contains(.mayBegin)
        ended = event.phase.contains(.ended) || event.phase.contains(.cancelled)
        isMomentum = !event.momentumPhase.isEmpty
        isPrecise = event.hasPreciseScrollingDeltas
    }
}
