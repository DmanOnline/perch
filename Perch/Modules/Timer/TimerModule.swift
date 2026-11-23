import AppKit
import Observation
import SwiftUI

/// A countdown that lives in the notch: start it from the tab with one click,
/// watch it run in the wings, feel and hear it end. Survives a restart.
@Observable
final class TimerModule: PerchModule {
    static let presets: [Int] = [1, 3, 5, 10, 15, 25, 45, 60]
    /// The alarm rings until dismissed, but never longer than this.
    static let alarmLimit: Duration = .seconds(120)

    let id = "timer"
    let title = "Timer"
    let symbol = "timer"
    let summary = "A countdown in the notch, with a tap and a chime when it ends."

    enum State: Equatable {
        case idle
        case running(end: Date, total: TimeInterval)
        case paused(remaining: TimeInterval, total: TimeInterval)
        case done
    }

    private(set) var state: State = .idle { didSet { save(); updateActivity() } }
    private(set) var activity: Activity?
    /// Minutes chosen last, offered first next time.
    var lastMinutes: Int {
        get { UserDefaults.standard.object(forKey: Key.lastMinutes) as? Int ?? 25 }
        set { UserDefaults.standard.set(newValue, forKey: Key.lastMinutes) }
    }

    @ObservationIgnored private var tick: Task<Void, Never>?
    @ObservationIgnored private var doneTask: Task<Void, Never>?
    @ObservationIgnored private var alarm: NSSound?

    private enum Key {
        static let end = "timer.end"
        static let total = "timer.total"
        static let pausedRemaining = "timer.pausedRemaining"
        static let lastMinutes = "timer.lastMinutes"
    }

    func start() {
        restore()
    }

    func stop() {
        tick?.cancel()
        silence()
    }

    // MARK: Control

    func begin(minutes: Int) {
        silence()
        lastMinutes = minutes
        let total = TimeInterval(minutes * 60)
        state = .running(end: .now + total, total: total)
    }

    func togglePause() {
        switch state {
        case let .running(end, total):
            state = .paused(remaining: max(end.timeIntervalSinceNow, 0), total: total)
        case let .paused(remaining, total):
            state = .running(end: .now + remaining, total: total)
        default:
            break
        }
    }

    func addMinute() {
        switch state {
        case let .running(end, total):
            state = .running(end: end + 60, total: total + 60)
        case let .paused(remaining, total):
            state = .paused(remaining: remaining + 60, total: total + 60)
        default:
            break
        }
    }

    /// Stops the timer, or silences and clears the alarm.
    func cancel() {
        silence()
        state = .idle
    }

    func remaining(at date: Date = .now) -> TimeInterval {
        switch state {
        case let .running(end, _): max(end.timeIntervalSince(date), 0)
        case let .paused(remaining, _): remaining
        default: 0
        }
    }

    func progress(at date: Date = .now) -> Double {
        switch state {
        case let .running(_, total), let .paused(_, total):
            total > 0 ? 1 - remaining(at: date) / total : 0
        case .done: 1
        case .idle: 0
        }
    }

    // MARK: Running

    private func updateActivity() {
        tick?.cancel()
        doneTask?.cancel()
        switch state {
        case .idle:
            activity = nil
        case let .running(end, _):
            // A running timer outranks music: it is about time.
            if activity?.id != "running" {
                activity = Activity(id: "running", moduleID: id, priority: .attention)
            }
            tick = Task { [weak self] in
                try? await Task.sleep(for: .seconds(max(end.timeIntervalSinceNow, 0)))
                guard !Task.isCancelled else { return }
                self?.finish()
            }
        case .paused:
            if activity?.id != "paused" {
                activity = Activity(id: "paused", moduleID: id, priority: .info)
            }
        case .done:
            // Stays until dismissed with OK, like a real alarm.
            activity = Activity(id: "done", moduleID: id, priority: .urgent)
        }
    }

    private func finish() {
        state = .done
        ring()
    }

    // MARK: Alarm

    /// The iPhone timer sound, looping, with a tap on the trackpad every few
    /// seconds, until OK is pressed or `alarmLimit` passes. Falls back to a
    /// standard macOS sound if the ringtone is ever missing.
    private func ring() {
        let radar = "/System/Library/PrivateFrameworks/ToneLibrary.framework/Versions/A/Resources/Ringtones/Radar.m4r"
        let sound = NSSound(contentsOfFile: radar, byReference: true) ?? NSSound(named: "Glass")
        sound?.loops = true
        sound?.volume = 1
        sound?.play()
        alarm = sound
        doneTask?.cancel()
        doneTask = Task { [weak self] in
            let start = ContinuousClock.now
            while !Task.isCancelled, ContinuousClock.now - start < Self.alarmLimit {
                Haptics.play(.event)
                try? await Task.sleep(for: .seconds(3))
            }
            self?.alarm?.stop()
        }
    }

    private func silence() {
        doneTask?.cancel()
        alarm?.stop()
        alarm = nil
    }

    // MARK: Persistence

    private func save() {
        let defaults = UserDefaults.standard
        switch state {
        case let .running(end, total):
            defaults.set(end.timeIntervalSince1970, forKey: Key.end)
            defaults.set(total, forKey: Key.total)
            defaults.removeObject(forKey: Key.pausedRemaining)
        case let .paused(remaining, total):
            defaults.set(remaining, forKey: Key.pausedRemaining)
            defaults.set(total, forKey: Key.total)
            defaults.removeObject(forKey: Key.end)
        case .idle, .done:
            for key in [Key.end, Key.total, Key.pausedRemaining] { defaults.removeObject(forKey: key) }
        }
    }

    private func restore() {
        let defaults = UserDefaults.standard
        let total = defaults.double(forKey: Key.total)
        if let end = defaults.object(forKey: Key.end) as? Double {
            let date = Date(timeIntervalSince1970: end)
            // A timer that ended while Perch was not running is simply over.
            state = date > .now ? .running(end: date, total: total) : .idle
        } else if let remaining = defaults.object(forKey: Key.pausedRemaining) as? Double {
            state = .paused(remaining: remaining, total: total)
        }
    }

    // MARK: Views

    func compactLeading() -> AnyView {
        AnyView(TimerCompactLeading(module: self))
    }

    func compactTrailing() -> AnyView {
        AnyView(TimerCompactTrailing(module: self))
    }

    func expanded() -> AnyView {
        AnyView(TimerExpandedView(module: self))
    }
}

enum TimerStyle {
    static let accent = Color(red: 1.0, green: 0.62, blue: 0.20)

    static func format(_ seconds: TimeInterval) -> String {
        let total = Int(seconds.rounded(.up))
        let (h, m, s) = (total / 3600, total / 60 % 60, total % 60)
        return h > 0 ? String(format: "%d:%02d:%02d", h, m, s) : String(format: "%d:%02d", m, s)
    }
}

/// A ring that empties as time runs out.
struct TimerRing: View {
    let progress: Double
    var size: CGFloat
    var lineWidth: CGFloat

    var body: some View {
        ZStack {
            Circle().stroke(TimerStyle.accent.opacity(0.22), lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: max(1 - progress, 0.001))
                .stroke(TimerStyle.accent, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
        }
        .frame(width: size, height: size)
    }
}

private struct TimerCompactLeading: View {
    let module: TimerModule

    var body: some View {
        Group {
            if module.state == .done {
                Image(systemName: "bell.fill")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(TimerStyle.accent)
                    .symbolEffect(.wiggle, options: .repeating)
            } else {
                TimelineView(.periodic(from: .now, by: 1)) { context in
                    TimerRing(progress: module.progress(at: context.date), size: 17, lineWidth: 2.6)
                        .animation(.linear(duration: 1), value: module.progress(at: context.date))
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.leading, 9)
    }
}

private struct TimerCompactTrailing: View {
    let module: TimerModule

    var body: some View {
        Group {
            if module.state == .done {
                Text("Done")
                    .foregroundStyle(TimerStyle.accent)
            } else {
                TimelineView(.periodic(from: .now, by: 1)) { context in
                    Text(TimerStyle.format(module.remaining(at: context.date)))
                        .monospacedDigit()
                        .foregroundStyle(isPaused ? .white.opacity(0.5) : TimerStyle.accent)
                        .contentTransition(.numericText(countsDown: true))
                        .animation(.snappy, value: Int(module.remaining(at: context.date)))
                }
            }
        }
        .font(.system(size: 13.5, weight: .bold))
        .frame(maxWidth: .infinity, alignment: .trailing)
        .padding(.trailing, 8)
    }

    private var isPaused: Bool {
        if case .paused = module.state { return true }
        return false
    }
}

private struct TimerExpandedView: View {
    let module: TimerModule
    @State private var minutes = 25

    var body: some View {
        Group {
            switch module.state {
            case .idle:
                picker
            case .running, .paused, .done:
                running
            }
        }
        .onAppear { minutes = module.lastMinutes }
    }

    /// Pick a time: one click on a preset starts it, or dial in minutes.
    private var picker: some View {
        HStack(spacing: 26) {
            VStack(spacing: 10) {
                HStack(spacing: 14) {
                    step("minus") { minutes = max(1, minutes - 1) }
                    VStack(spacing: 0) {
                        Text("\(minutes)")
                            .font(.system(size: 44, weight: .bold, design: .rounded))
                            .monospacedDigit()
                            .contentTransition(.numericText(value: Double(minutes)))
                            .animation(.snappy, value: minutes)
                        Text("min")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(.white.opacity(0.5))
                    }
                    .frame(width: 80)
                    step("plus") { minutes = min(180, minutes + 1) }
                }
                Button {
                    Haptics.play(.tap)
                    module.begin(minutes: minutes)
                } label: {
                    Text("Start")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(.black)
                        .frame(width: 120, height: 28)
                        .background(Capsule().fill(TimerStyle.accent))
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
            }

            LazyVGrid(columns: Array(repeating: GridItem(.fixed(58), spacing: 8), count: 4), spacing: 8) {
                ForEach(TimerModule.presets, id: \.self) { preset in
                    Button {
                        Haptics.play(.tap)
                        module.begin(minutes: preset)
                    } label: {
                        Text(preset == 60 ? "1 h" : "\(preset) min")
                            .font(.system(size: 12.5, weight: .semibold))
                            .foregroundStyle(.white.opacity(0.9))
                            .frame(width: 58, height: 32)
                            .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(.white.opacity(0.09)))
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .frame(maxWidth: .infinity)
    }

    private var running: some View {
        HStack(spacing: 30) {
            TimelineView(.periodic(from: .now, by: 1)) { context in
                ZStack {
                    TimerRing(progress: module.progress(at: context.date), size: 104, lineWidth: 8)
                        .animation(.linear(duration: 1), value: module.progress(at: context.date))
                    if module.state == .done {
                        Image(systemName: "bell.fill")
                            .font(.system(size: 30, weight: .semibold))
                            .foregroundStyle(TimerStyle.accent)
                            .symbolEffect(.wiggle, options: .repeating)
                    } else {
                        Text(TimerStyle.format(module.remaining(at: context.date)))
                            .font(.system(size: 24, weight: .bold, design: .rounded))
                            .monospacedDigit()
                            .contentTransition(.numericText(countsDown: true))
                            .animation(.snappy, value: Int(module.remaining(at: context.date)))
                    }
                }
            }

            HStack(spacing: 14) {
                if module.state == .done {
                    control("checkmark", label: "OK", prominent: true) { module.cancel() }
                    control("arrow.clockwise", label: "Again") { module.begin(minutes: module.lastMinutes) }
                } else {
                    control(isPaused ? "play.fill" : "pause.fill", label: isPaused ? "Resume" : "Pause", prominent: true) {
                        module.togglePause()
                    }
                    control("plus", label: "1 min") { module.addMinute() }
                    control("xmark", label: "Stop") { module.cancel() }
                }
            }
        }
        .frame(maxWidth: .infinity)
    }

    private var isPaused: Bool {
        if case .paused = module.state { return true }
        return false
    }

    private func step(_ symbol: String, action: @escaping () -> Void) -> some View {
        Button {
            Haptics.play(.tap)
            action()
        } label: {
            Image(systemName: symbol)
                .font(.system(size: 14, weight: .bold))
                .frame(width: 32, height: 32)
                .background(Circle().fill(.white.opacity(0.1)))
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .buttonRepeatBehavior(.enabled)
    }

    private func control(_ symbol: String, label: String, prominent: Bool = false, action: @escaping () -> Void) -> some View {
        Button {
            Haptics.play(.tap)
            action()
        } label: {
            VStack(spacing: 6) {
                Image(systemName: symbol)
                    .font(.system(size: 17, weight: .bold))
                    .foregroundStyle(prominent ? .black : .white)
                    .frame(width: 48, height: 48)
                    .background(Circle().fill(prominent ? TimerStyle.accent : .white.opacity(0.12)))
                Text(label)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.6))
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
