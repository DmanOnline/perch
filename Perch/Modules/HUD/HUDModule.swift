import AppKit
import Observation
import SwiftUI

/// Volume and brightness, out of the notch instead of Apple's grey box.
/// With Accessibility permission Perch catches the keys, changes the level
/// itself and macOS shows nothing; without it Perch follows volume changes
/// and shows them beside the system pop-up.
@Observable
final class HUDModule: PerchModule {
    enum Kind: Equatable { case volume, brightness }

    static let display: Duration = .milliseconds(1600)
    /// One key press, as macOS does it: sixteen steps from silent to full.
    static let step: Float = 1.0 / 16
    /// Option + Shift + key: a quarter step, also as macOS does it.
    static let fineStep: Float = 1.0 / 64

    let id = "hud"
    let title = "Volume & Brightness"
    let symbol = "speaker.wave.2.fill"
    let summary = "Volume and brightness slide out of the notch instead of the grey pop-up."
    /// No tab: the sliders appear when you hover over the pop-up.
    let tabID = "none"

    private(set) var activity: Activity?
    private(set) var kind: Kind = .volume
    private(set) var volume: Float = SystemVolume.volume ?? 0.5
    private(set) var isMuted = SystemVolume.isMuted
    private(set) var brightness: Float = SystemBrightness.brightness ?? 0.5
    private(set) var catchesKeys = false

    @ObservationIgnored private let tap = MediaKeyTap()
    @ObservationIgnored private let watcher = VolumeWatcher()
    @ObservationIgnored private var hideTask: Task<Void, Never>?
    @ObservationIgnored private var permissionPoll: Task<Void, Never>?
    /// Changes Perch makes itself also come back through the watcher; this
    /// keeps them from being shown twice.
    @ObservationIgnored private var lastOwnChange = Date.distantPast

    func start() {
        watcher.start { [weak self] in self?.volumeChangedOutside() }
        startCatchingKeys()
    }

    func stop() {
        tap.stop()
        watcher.stop()
        permissionPoll?.cancel()
        hideTask?.cancel()
        catchesKeys = false
    }

    /// Asks macOS for Accessibility permission and starts catching the keys
    /// as soon as it is granted.
    func requestKeyAccess() {
        MediaKeyTap.requestPermission()
        permissionPoll?.cancel()
        permissionPoll = Task { [weak self] in
            for _ in 0..<120 {
                try? await Task.sleep(for: .seconds(1))
                guard !Task.isCancelled, let self else { return }
                if MediaKeyTap.hasPermission {
                    self.startCatchingKeys()
                    return
                }
            }
        }
    }

    private func startCatchingKeys() {
        catchesKeys = tap.start { [weak self] key, flags in self?.handle(key, flags: flags) }
    }

    // MARK: Changing levels

    private func handle(_ key: MediaKey, flags: NSEvent.ModifierFlags) {
        let fine = flags.contains(.option) && flags.contains(.shift)
        let step = fine ? Self.fineStep : Self.step
        switch key {
        case .volumeUp: setVolume(volume + step)
        case .volumeDown: setVolume(volume - step)
        case .mute: setMuted(!isMuted)
        case .brightnessUp: setBrightness(brightness + step)
        case .brightnessDown: setBrightness(brightness - step)
        }
    }

    func setVolume(_ value: Float) {
        let level = (min(max(value, 0), 1) / Self.fineStep).rounded() * Self.fineStep
        lastOwnChange = .now
        SystemVolume.setVolume(level)
        volume = level
        isMuted = level == 0 ? isMuted : false
        show(.volume)
    }

    func setMuted(_ muted: Bool) {
        lastOwnChange = .now
        SystemVolume.setMuted(muted)
        isMuted = muted
        show(.volume)
    }

    func setBrightness(_ value: Float) {
        let level = (min(max(value, 0), 1) / Self.fineStep).rounded() * Self.fineStep
        SystemBrightness.setBrightness(level)
        brightness = level
        show(.brightness)
    }

    private func volumeChangedOutside() {
        let newVolume = SystemVolume.volume ?? volume
        let newMuted = SystemVolume.isMuted
        guard newVolume != volume || newMuted != isMuted else { return }
        volume = newVolume
        isMuted = newMuted
        // Our own key presses arrive here too; they already showed.
        guard Date.now.timeIntervalSince(lastOwnChange) > 0.3 else { return }
        show(.volume)
    }

    private func show(_ kind: Kind) {
        self.kind = kind
        if activity == nil {
            activity = Activity(id: "level", moduleID: id, priority: .urgent)
        }
        hideTask?.cancel()
        hideTask = Task { [weak self] in
            try? await Task.sleep(for: Self.display)
            guard !Task.isCancelled else { return }
            self?.activity = nil
        }
    }

    /// Keeps the pop-up while the pointer is on the sliders; leaving starts
    /// the usual countdown again.
    func holdOpen(_ holding: Bool) {
        if holding {
            hideTask?.cancel()
        } else if activity != nil {
            show(kind)
        }
    }

    // MARK: Views

    var levelSymbol: String {
        switch kind {
        case .volume: isMuted || volume == 0 ? "speaker.slash.fill" : "speaker.wave.3.fill"
        case .brightness: "sun.max.fill"
        }
    }

    var level: Float {
        kind == .volume ? (isMuted ? 0 : volume) : brightness
    }

    func compactLeading() -> AnyView {
        AnyView(HUDCompactLeading(module: self))
    }

    func compactTrailing() -> AnyView {
        AnyView(HUDCompactTrailing(module: self))
    }

    func expanded() -> AnyView {
        AnyView(HUDExpandedView(module: self))
    }

    func settings() -> AnyView? {
        AnyView(HUDSettingsView(module: self))
    }
}

private struct HUDCompactLeading: View {
    let module: HUDModule

    var body: some View {
        Image(systemName: module.levelSymbol, variableValue: Double(module.level))
            .font(.system(size: 14, weight: .semibold))
            .foregroundStyle(.white)
            .contentTransition(.symbolEffect(.replace))
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.leading, 9)
    }
}

private struct HUDCompactTrailing: View {
    let module: HUDModule

    var body: some View {
        LevelBar(level: module.level)
            .frame(width: 56, height: 6)
            .frame(maxWidth: .infinity, alignment: .trailing)
            .padding(.trailing, 10)
    }
}

/// A slim bar that fills with the level, like the iPhone's volume pop-up.
private struct LevelBar: View {
    let level: Float

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule().fill(.white.opacity(0.2))
                Capsule().fill(.white)
                    .frame(width: proxy.size.width * CGFloat(level))
            }
        }
        .animation(.spring(response: 0.25, dampingFraction: 0.9), value: level)
    }
}

/// Hovering over the pop-up opens both sliders, to drag instead of tap.
private struct HUDExpandedView: View {
    let module: HUDModule

    var body: some View {
        VStack(spacing: 22) {
            row(symbol: module.isMuted ? "speaker.slash.fill" : "speaker.wave.3.fill",
                value: Binding(get: { Double(module.isMuted ? 0 : module.volume) },
                               set: { module.setVolume(Float($0)) })) {
                module.setMuted(!module.isMuted)
            }
            if SystemBrightness.brightness != nil {
                row(symbol: "sun.max.fill",
                    value: Binding(get: { Double(module.brightness) }, set: { module.setBrightness(Float($0)) }),
                    tap: nil)
            }
        }
        .padding(.horizontal, 30)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onHover { module.holdOpen($0) }
    }

    private func row(symbol: String, value: Binding<Double>, tap: (() -> Void)?) -> some View {
        HStack(spacing: 16) {
            Button {
                tap?()
            } label: {
                Image(systemName: symbol)
                    .font(.system(size: 16, weight: .semibold))
                    .frame(width: 30, height: 30)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(tap == nil)
            Slider(value: value, in: 0...1)
                .tint(.white)
            Text("\(Int((value.wrappedValue * 100).rounded()))")
                .font(.system(size: 13, weight: .semibold).monospacedDigit())
                .foregroundStyle(.white.opacity(0.6))
                .frame(width: 32, alignment: .trailing)
        }
        .foregroundStyle(.white)
    }
}

private struct HUDSettingsView: View {
    let module: HUDModule

    var body: some View {
        SettingRow("Replace the macOS pop-up", hint: module.catchesKeys
                   ? "Perch handles the volume and brightness keys; macOS shows nothing."
                   : "Needs Accessibility permission to catch the keys. Until then Perch only follows the volume.",
                   last: true) {
            if module.catchesKeys {
                Label("On", systemImage: "checkmark.circle.fill")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(SettingsStyle.accent)
            } else {
                Button("Allow…") { module.requestKeyAccess() }
                    .controlSize(.small)
            }
        }
    }
}
