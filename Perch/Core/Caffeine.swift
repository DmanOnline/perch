import Foundation
import IOKit.pwr_mgt
import Observation

/// Keeps the Mac and its display awake, for a while or until switched off,
/// with the same power assertion `caffeinate -d` uses.
@Observable
final class Caffeine {
    static let shared = Caffeine()

    static let durations: [(label: String, minutes: Int?)] = [
        ("30 minutes", 30), ("1 hour", 60), ("2 hours", 120), ("Until turned off", nil),
    ]

    private(set) var isActive = false
    /// When it switches itself off; nil while it runs until turned off.
    private(set) var endsAt: Date?

    @ObservationIgnored private var assertion: IOPMAssertionID = 0
    @ObservationIgnored private var timer: Task<Void, Never>?

    func toggle() {
        isActive ? stop() : start(minutes: nil)
    }

    func start(minutes: Int?) {
        stop()
        let reason = "Perch: keep awake" as CFString
        guard IOPMAssertionCreateWithName(kIOPMAssertionTypePreventUserIdleDisplaySleep as CFString,
                                          IOPMAssertionLevel(kIOPMAssertionLevelOn), reason, &assertion) == kIOReturnSuccess
        else { return }
        isActive = true
        Haptics.play(.tap)
        guard let minutes else { return }
        let end = Date.now + TimeInterval(minutes * 60)
        endsAt = end
        timer = Task { [weak self] in
            try? await Task.sleep(for: .seconds(end.timeIntervalSinceNow))
            guard !Task.isCancelled else { return }
            self?.stop()
        }
    }

    func stop() {
        timer?.cancel()
        timer = nil
        if isActive { IOPMAssertionRelease(assertion) }
        assertion = 0
        isActive = false
        endsAt = nil
    }
}
