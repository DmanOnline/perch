import SwiftUI

enum ChargingStyle {
    /// Apple's system green on dark.
    static let green = Color(red: 0.204, green: 0.780, blue: 0.349)

    /// Energy pulses that run into the battery, and when each one lands.
    static let pulses = 3
    static let firstPulse = 0.35
    static let pulseInterval = 0.75
    static let pulseTravel = 0.65

    static func arrival(of pulse: Int) -> Double {
        firstPulse + Double(pulse) * pulseInterval + pulseTravel
    }
}

/// The power-connected moment, modelled on the Dynamic Island: "Charging"
/// on the left, a green battery with the level on the right. Both slide out
/// from under the notch (see `NotchView.wings`) and fill as energy flows in.
struct ChargingLeading: View {
    /// False when power is connected but the battery is not taking charge
    /// (full, or held back by optimised charging).
    let isCharging: Bool

    var body: some View {
        Text(isCharging ? "Charging" : "Connected")
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(.white)
            .lineLimit(1)
            .fixedSize()
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.leading, 6)
    }
}

struct ChargingTrailing: View {
    let percent: Int
    /// Pulses absorbed so far; the battery fills one step per pulse.
    @State private var absorbed = 0
    @State private var flash = false

    private var level: Double {
        let target = Double(percent) / 100
        return 0.05 + (target - 0.05) * Double(absorbed) / Double(ChargingStyle.pulses)
    }

    var body: some View {
        HStack(spacing: 5) {
            Text("\(percent)%")
                .font(.system(size: 13, weight: .semibold))
                .monospacedDigit()
                .foregroundStyle(ChargingStyle.green)
            ChargingBattery(level: level, flash: flash)
        }
        .fixedSize()
        .frame(maxWidth: .infinity, alignment: .trailing)
        .padding(.trailing, Self.trailingInset)
        .task {
            var elapsed = 0.0
            for pulse in 0..<ChargingStyle.pulses {
                let landing = ChargingStyle.arrival(of: pulse)
                try? await Task.sleep(for: .seconds(landing - elapsed))
                elapsed = landing
                // Each pulse of energy is felt as it lands.
                Haptics.play(.tap)
                withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) { absorbed = pulse + 1 }
                withAnimation(.easeOut(duration: 0.08)) { flash = true }
                withAnimation(.easeOut(duration: 0.45).delay(0.08)) { flash = false }
            }
        }
    }

    static let trailingInset: CGFloat = 6
    /// Distance from the wing's outer edge to the centre of the battery,
    /// where the energy pulses aim.
    static let batteryCentreInset: CGFloat = trailingInset + 6.5
}

/// Pulses of light that run along the bottom edge of the notch, from the far
/// left into the battery on the right, speeding up as they go, and vanish
/// into it. The battery fills a step as each one lands.
struct EnergyFlow: View {
    @State private var start = Date.now

    var body: some View {
        TimelineView(.animation) { context in
            let t = context.date.timeIntervalSince(start)
            GeometryReader { proxy in
                let target = proxy.size.width - NotchMetrics.earRadius(for: .compact) - ChargingTrailing.batteryCentreInset
                ZStack(alignment: .topLeading) {
                    ForEach(0..<ChargingStyle.pulses, id: \.self) { pulse in
                        let launch = ChargingStyle.firstPulse + Double(pulse) * ChargingStyle.pulseInterval
                        let p = (t - launch) / ChargingStyle.pulseTravel
                        if p > 0, p < 1 {
                            Pulse(progress: p, target: target, height: proxy.size.height)
                        }
                    }
                }
            }
        }
        .onAppear { start = .now }
    }

    private struct Pulse: View {
        let progress: Double
        let target: CGFloat
        let height: CGFloat

        var body: some View {
            // Ease in: energy gathers speed on its way into the battery.
            let eased = progress * progress
            let length: CGFloat = 46 + 40 * eased
            let x = -length + (target + length) * eased
            // Fade out over the last stretch, as it is absorbed.
            let fade = progress > 0.8 ? (1 - progress) / 0.2 : min(progress / 0.15, 1)
            ZStack {
                Capsule()
                    .fill(LinearGradient(colors: [.clear, ChargingStyle.green.opacity(0.7)],
                                         startPoint: .leading, endPoint: .trailing))
                    .frame(width: length, height: 5)
                    .blur(radius: 4)
                Capsule()
                    .fill(LinearGradient(colors: [.clear, ChargingStyle.green, .white],
                                         startPoint: .leading, endPoint: .trailing))
                    .frame(width: length, height: 1.6)
            }
            .blendMode(.plusLighter)
            .opacity(fade)
            .offset(x: x, y: height - 4)
        }
    }
}

/// The battery glyph as iOS draws it in the island: a rounded body, a cap,
/// a green fill and a bolt cut into it.
private struct ChargingBattery: View {
    let level: Double
    var flash = false

    var body: some View {
        HStack(spacing: 1.5) {
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .fill(.white.opacity(0.28))
                GeometryReader { proxy in
                    RoundedRectangle(cornerRadius: 2.5, style: .continuous)
                        .fill(ChargingStyle.green)
                        .brightness(flash ? 0.35 : 0)
                        .shadow(color: ChargingStyle.green.opacity(flash ? 0.9 : 0), radius: 4)
                        .frame(width: proxy.size.width * level)
                }
                .padding(1.5)
                Image(systemName: "bolt.fill")
                    .font(.system(size: 8, weight: .black))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
            }
            .frame(width: 25, height: 12)
            UnevenRoundedRectangle(topLeadingRadius: 0, bottomLeadingRadius: 0,
                                   bottomTrailingRadius: 1.5, topTrailingRadius: 1.5)
                .fill(.white.opacity(0.28))
                .frame(width: 1.5, height: 4.5)
        }
    }
}
