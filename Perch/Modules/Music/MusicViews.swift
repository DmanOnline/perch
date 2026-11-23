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

/// Four bars that dance while playing and rest low while paused.
///
/// Drawn with Core Animation so the render server runs the loop; a SwiftUI
/// timeline here kept Perch at about 12% CPU the whole time music played.
struct EqualizerView: NSViewRepresentable {
    let isPlaying: Bool
    let color: Color

    func makeNSView(context: Context) -> EqualizerBarsView { EqualizerBarsView() }

    func updateNSView(_ view: EqualizerBarsView, context: Context) {
        view.update(isPlaying: isPlaying, color: NSColor(color).cgColor)
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

    private var bars: [CALayer] = []
    private var isPlaying: Bool?

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

    func update(isPlaying: Bool, color: CGColor) {
        for bar in bars { bar.backgroundColor = color }
        guard isPlaying != self.isPlaying else { return }
        self.isPlaying = isPlaying
        for (index, bar) in bars.enumerated() {
            let current = bar.presentation()?.transform ?? bar.transform
            bar.removeAllAnimations()
            if isPlaying {
                let values = Self.patterns[index]
                let dance = CAKeyframeAnimation(keyPath: "transform.scale.y")
                dance.values = values + [values[0]]
                dance.duration = Double(values.count) * 0.19
                dance.calculationMode = .cubic
                dance.repeatCount = .infinity
                dance.isRemovedOnCompletion = false
                bar.add(dance, forKey: "dance")
            } else {
                bar.transform = CATransform3DMakeScale(1, Self.restScale, 1)
                let settle = CABasicAnimation(keyPath: "transform")
                settle.fromValue = current
                settle.duration = 0.25
                settle.timingFunction = CAMediaTimingFunction(name: .easeOut)
                bar.add(settle, forKey: "settle")
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
        Button(action: action) {
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
