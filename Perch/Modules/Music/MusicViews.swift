import SwiftUI

struct ArtworkView: View {
    let image: NSImage?
    let size: CGFloat
    let radius: CGFloat

    var body: some View {
        ZStack {
            if let image {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .transition(.opacity)
            } else {
                Rectangle()
                    .fill(.white.opacity(0.1))
                Image(systemName: "music.note")
                    .font(.system(size: size * 0.42, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.5))
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
        .animation(.smooth(duration: 0.3), value: image)
    }
}

/// Four bars that dance while playing and rest low while paused. In live
/// mode they follow the real sound instead (see `LiveAudio`), and fall back
/// to the dance when there is nothing to hear, for instance when macOS was
/// not allowed to share the system audio.
///
/// Drawn with Core Animation so the render server runs the loop; a SwiftUI
/// timeline here kept Perch at about 12% CPU the whole time music played.
struct EqualizerView: NSViewRepresentable {
    let isPlaying: Bool
    let color: Color
    var live = false

    func makeNSView(context: Context) -> EqualizerBarsView { EqualizerBarsView() }

    func updateNSView(_ view: EqualizerBarsView, context: Context) {
        view.update(isPlaying: isPlaying, live: live, color: NSColor(color).cgColor)
    }

    static func dismantleNSView(_ view: EqualizerBarsView, coordinator: ()) {
        view.stopListening()
    }
}

final class EqualizerBarsView: NSView {
    private static let barCount = 4
    private static let barWidth: CGFloat = 2.5
    private static let spacing: CGFloat = 2
    private static let maxHeight: CGFloat = 14
    private static let restScale: CGFloat = 0.22
    /// Scale keyframes per bar; different lengths keep the bars out of step.
    private static let patterns: [[CGFloat]] = [
        [0.35, 0.9, 0.5, 1.0, 0.3, 0.75],
        [0.8, 0.4, 1.0, 0.55, 0.9],
        [0.5, 1.0, 0.3, 0.85, 0.6, 0.95, 0.4],
        [0.9, 0.45, 0.7, 0.3, 1.0],
    ]
    /// Without sound for this long, live mode dances instead of lying flat.
    private static let silenceBeforeDance: TimeInterval = 3

    private enum Motion { case rest, dance, live }

    private var bars: [CALayer] = []
    private var motion: Motion?
    private var wantsLive = false
    private var isPlaying = false
    private var listening = false
    private var link: CADisplayLink?

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        for _ in 0..<Self.barCount {
            let bar = CALayer()
            bar.cornerRadius = Self.barWidth / 2
            bar.transform = CATransform3DMakeScale(1, Self.restScale, 1)
            layer?.addSublayer(bar)
            bars.append(bar)
        }
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override var intrinsicContentSize: NSSize {
        NSSize(width: CGFloat(Self.barCount) * (Self.barWidth + Self.spacing) - Self.spacing, height: Self.maxHeight)
    }

    override func layout() {
        super.layout()
        let width = intrinsicContentSize.width
        var x = (bounds.width - width) / 2
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        for bar in bars {
            bar.bounds = CGRect(x: 0, y: 0, width: Self.barWidth, height: Self.maxHeight)
            bar.position = CGPoint(x: x + Self.barWidth / 2, y: bounds.midY)
            x += Self.barWidth + Self.spacing
        }
        CATransaction.commit()
    }

    func update(isPlaying: Bool, live: Bool, color: CGColor) {
        for bar in bars { bar.backgroundColor = color }
        self.isPlaying = isPlaying
        wantsLive = live
        if isPlaying && live && window != nil { startListening() } else { stopListening() }
        if !isPlaying {
            apply(.rest)
        } else if !live {
            apply(.dance)
        } else if motion == nil || motion == .rest {
            // Live levels take over on the next frame; until there is sound,
            // the bars dance.
            apply(.dance)
        }
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window == nil { stopListening() } else if isPlaying && wantsLive { startListening() }
    }

    private func startListening() {
        guard !listening else { return }
        listening = true
        LiveAudio.shared.acquire()
        let link = displayLink(target: self, selector: #selector(frame(_:)))
        link.add(to: .main, forMode: .common)
        self.link = link
    }

    func stopListening() {
        link?.invalidate()
        link = nil
        guard listening else { return }
        listening = false
        LiveAudio.shared.release()
    }

    @objc private func frame(_ link: CADisplayLink) {
        let audio = LiveAudio.shared
        let quietFor = audio.lastSignal.map { -$0.timeIntervalSinceNow } ?? .infinity
        guard !audio.failed, quietFor < Self.silenceBeforeDance else {
            apply(.dance)
            return
        }
        apply(.live)
        let levels = audio.levels
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        for (index, bar) in bars.enumerated() {
            let level = CGFloat(levels[min(index, levels.count - 1)])
            bar.transform = CATransform3DMakeScale(1, Self.restScale + (1 - Self.restScale) * level, 1)
        }
        CATransaction.commit()
    }

    private func apply(_ next: Motion) {
        guard next != motion else { return }
        let previous = motion
        motion = next
        for (index, bar) in bars.enumerated() {
            let current = bar.presentation()?.transform ?? bar.transform
            bar.removeAllAnimations()
            switch next {
            case .dance:
                let values = Self.patterns[index]
                let dance = CAKeyframeAnimation(keyPath: "transform.scale.y")
                dance.values = values + [values[0]]
                dance.duration = Double(values.count) * 0.19
                dance.calculationMode = .cubic
                dance.repeatCount = .infinity
                dance.isRemovedOnCompletion = false
                bar.add(dance, forKey: "dance")
            case .rest:
                guard previous != nil else { continue }
                bar.transform = CATransform3DMakeScale(1, Self.restScale, 1)
                let settle = CABasicAnimation(keyPath: "transform")
                settle.fromValue = current
                settle.duration = 0.25
                settle.timingFunction = CAMediaTimingFunction(name: .easeOut)
                bar.add(settle, forKey: "settle")
            case .live:
                // Start from where the dance was, so the hand-over is seamless.
                CATransaction.begin()
                CATransaction.setDisableActions(true)
                bar.transform = current
                CATransaction.commit()
            }
        }
    }
}

struct MusicExpandedView: View {
    let module: MusicModule

    var body: some View {
        if let playing = module.nowPlaying {
            HStack(spacing: 16) {
                Button(action: module.openSourceApp) {
                    ArtworkView(image: module.artwork, size: 100, radius: 14)
                        .shadow(color: module.accent.opacity(0.35), radius: 14, y: 4)
                }
                .buttonStyle(.plain)
                .help("Open the app that is playing")

                VStack(alignment: .leading, spacing: 0) {
                    Text(playing.title)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                    Text(playing.artist.isEmpty ? playing.album : playing.artist)
                        .font(.system(size: 13))
                        .foregroundStyle(.white.opacity(0.55))
                        .lineLimit(1)
                    Spacer(minLength: 8)
                    ProgressRow(playing: playing, accent: module.accent) { seconds in
                        module.service.seek(to: seconds)
                    }
                    Spacer(minLength: 6)
                    Controls(isPlaying: playing.isPlaying) { command in
                        module.service.send(command)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .frame(height: 100)
            }
        } else {
            VStack(spacing: 8) {
                Image(systemName: module.service.isAvailable ? "music.note" : "exclamationmark.triangle")
                    .font(.system(size: 28, weight: .semibold))
                Text(module.service.isAvailable ? "Nothing playing" : "Now Playing is unavailable on this Mac")
                    .font(.system(size: 13))
            }
            .foregroundStyle(.white.opacity(0.5))
        }
    }
}

private struct ProgressRow: View {
    let playing: NowPlaying
    let accent: Color
    let onSeek: (TimeInterval) -> Void

    @State private var dragProgress: Double?

    var body: some View {
        TimelineView(.periodic(from: .now, by: 0.5)) { context in
            let progress = dragProgress ?? playing.progress(at: context.date) ?? 0
            let duration = playing.duration ?? 0
            VStack(spacing: 4) {
                GeometryReader { proxy in
                    ZStack(alignment: .leading) {
                        Capsule().fill(.white.opacity(0.15))
                        Capsule().fill(accent)
                            .frame(width: proxy.size.width * progress)
                    }
                    .frame(height: dragProgress == nil ? 4 : 6)
                    .frame(maxHeight: .infinity)
                    .contentShape(Rectangle())
                    .gesture(
                        DragGesture(minimumDistance: 0)
                            .onChanged { value in
                                dragProgress = min(max(value.location.x / proxy.size.width, 0), 1)
                            }
                            .onEnded { _ in
                                if let dragProgress, duration > 0 { onSeek(dragProgress * duration) }
                                dragProgress = nil
                            }
                    )
                    .animation(.smooth(duration: 0.15), value: dragProgress == nil)
                }
                .frame(height: 10)
                .disabled(duration == 0)

                HStack {
                    Text(Self.format(progress * duration))
                    Spacer()
                    Text("-" + Self.format(max(duration - progress * duration, 0)))
                }
                .font(.system(size: 10, weight: .medium).monospacedDigit())
                .foregroundStyle(.white.opacity(0.45))
                .opacity(duration > 0 ? 1 : 0)
            }
        }
    }

    static func format(_ seconds: TimeInterval) -> String {
        let total = Int(seconds.rounded(.down))
        let (hours, minutes, secs) = (total / 3600, total / 60 % 60, total % 60)
        return hours > 0
            ? String(format: "%d:%02d:%02d", hours, minutes, secs)
            : String(format: "%d:%02d", minutes, secs)
    }
}

private struct Controls: View {
    let isPlaying: Bool
    let send: (MediaCommand) -> Void

    var body: some View {
        HStack(spacing: 22) {
            button("backward.fill", size: 15) { send(.previousTrack) }
            button(isPlaying ? "pause.fill" : "play.fill", size: 22) { send(.togglePlayPause) }
                .contentTransition(.symbolEffect(.replace))
            button("forward.fill", size: 15) { send(.nextTrack) }
        }
        .foregroundStyle(.white)
        .frame(maxWidth: .infinity)
    }

    private func button(_ symbol: String, size: CGFloat, action: @escaping () -> Void) -> some View {
        Button {
            Haptics.play(.tap)
            action()
        } label: {
            Image(systemName: symbol)
                .font(.system(size: size, weight: .semibold))
                .frame(width: 32, height: 28)
                .contentShape(Rectangle())
        }
        .buttonStyle(PressableStyle())
    }
}

private struct PressableStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.86 : 1)
            .opacity(configuration.isPressed ? 0.7 : 1)
            .animation(.spring(response: 0.25, dampingFraction: 0.6), value: configuration.isPressed)
    }
}

struct MusicSettingsView: View {
    @Bindable private var preferences = Preferences.shared

    var body: some View {
        SettingRow("Equalizer", hint: preferences.musicVisualizer == .live
                   ? "Moves with what you hear. macOS asks once to let Perch read system audio; it only measures, nothing is recorded."
                   : "A gentle dance while music plays. No permission needed.") {
            ChipPicker(selection: $preferences.musicVisualizer, options: [
                (.animated, "Animated"),
                (.live, "Live"),
            ])
        }
        SettingRow("Stay after pause", hint: preferences.musicLinger == 0
                   ? "The notch lets go as soon as you pause."
                   : "Keeps the notch this long after you pause.", last: true) {
            HStack(spacing: 10) {
                Slider(value: $preferences.musicLinger.snapped(to: 1), in: 0...30)
                    .frame(width: 130)
                Text(preferences.musicLinger == 0 ? "Off" : "\(Int(preferences.musicLinger)) s")
                    .font(.system(size: 12, weight: .medium).monospacedDigit())
                    .foregroundStyle(SettingsStyle.secondary)
                    .frame(width: 32, alignment: .trailing)
            }
        }
    }
}
