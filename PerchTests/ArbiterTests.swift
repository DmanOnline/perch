import Foundation
import Testing
@testable import Perch

struct ArbiterTests {
    private let now = Date(timeIntervalSinceReferenceDate: 1_000)

    @Test func emptyHasNoWinner() {
        #expect(Arbiter.select([], now: now) == nil)
    }

    @Test func higherPriorityWins() {
        let info = Activity(id: "a", moduleID: "m", priority: .info, startedAt: now)
        let urgent = Activity(id: "b", moduleID: "m", priority: .urgent, startedAt: now - 60)
        #expect(Arbiter.select([info, urgent], now: now)?.id == "b")
    }

    @Test func newerWinsAtEqualPriority() {
        let older = Activity(id: "old", moduleID: "m", priority: .attention, startedAt: now - 10)
        let newer = Activity(id: "new", moduleID: "m", priority: .attention, startedAt: now - 1)
        #expect(Arbiter.select([newer, older], now: now)?.id == "new")
        #expect(Arbiter.select([older, newer], now: now)?.id == "new")
    }

    @Test func expiredActivitiesAreIgnored() {
        let expired = Activity(id: "x", moduleID: "m", priority: .urgent, startedAt: now - 10, expiresAt: now)
        let live = Activity(id: "y", moduleID: "m", priority: .background, startedAt: now - 10)
        #expect(Arbiter.select([expired, live], now: now)?.id == "y")
    }
}
