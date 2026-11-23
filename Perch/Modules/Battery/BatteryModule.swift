import Foundation
import IOKit.ps
import Observation
import SwiftUI

nonisolated struct BatteryReading: Equatable, Sendable {
    var percent: Int
    var isCharging: Bool
    var isPluggedIn: Bool
    /// macOS considers the battery full (its own flag, not a guess from the percentage).
    var isCharged = false
    /// Minutes until full while charging, until empty on battery; nil while
    /// macOS is still estimating or when it does not apply.
    var minutesRemaining: Int? = nil
}

/// Battery level and charging. Lights up the notch when power is connected
/// and while the battery is low.
@Observable
final class BatteryModule: PerchModule {
    static var lowThreshold: Int { Preferences.shared.batteryLowThreshold }
    static let pluggedInDisplay: Duration = .seconds(5)

    let id = "battery"
    let title = "Battery"
    let summary = "Lights up when power connects and when the battery runs low."
    var symbol: String { reading.map(Self.symbol(for:)) ?? "battery.100" }

    private(set) var reading: BatteryReading?
    private(set) var activity: Activity?

    @ObservationIgnored private var runLoopSource: CFRunLoopSource?
    @ObservationIgnored private var clearTask: Task<Void, Never>?
    @ObservationIgnored private var debugObserver: NSObjectProtocol?
    /// AirPods and headphones, shown beside the Mac's battery in the tab.
    @ObservationIgnored weak var devices: DevicesModule?

    func start() {
        refresh()
        #if DEBUG
        // Replays the plug-in moment without a cable, for tuning and demos:
        // post the distributed notification "app.perch.debug.plugIn".
        debugObserver = DistributedNotificationCenter.default().addObserver(
            forName: Notification.Name("app.perch.debug.plugIn"), object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.celebratePlugIn() }
        }
        #endif
        let context = Unmanaged.passUnretained(self).toOpaque()
        guard let source = IOPSNotificationCreateRunLoopSource(powerSourcesChanged, context)?.takeRetainedValue() else { return }
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        runLoopSource = source
    }

    func stop() {
        if let runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
        }
        runLoopSource = nil
        clearTask?.cancel()
    }

    func refresh() {
        let previous = reading
        reading = Self.read()
        guard let reading else {
            activity = nil
            return
        }
        if reading.isPluggedIn, previous?.isPluggedIn == false, Preferences.shared.batteryShowOnPlugIn {
            celebratePlugIn()
        } else if !reading.isPluggedIn, reading.percent <= Self.lowThreshold {
            clearTask?.cancel()
            if activity?.id != "low" {
                activity = Activity(id: "low", moduleID: id, priority: .attention)
            }
        } else if activity?.id == "low" {
            activity = nil
        }
    }

    /// Power connected: the notch lights up with the charging animation.
    func celebratePlugIn() {
        Haptics.play(.event)
        show(Activity(
            id: Self.pluggedInActivity,
            moduleID: id,
            priority: .attention,
            expiresAt: .now + 5
        ), for: Self.pluggedInDisplay)
    }

    static let pluggedInActivity = "plugged-in"

    private func show(_ newActivity: Activity, for duration: Duration) {
        clearTask?.cancel()
        activity = newActivity
        clearTask = Task { [weak self] in
            try? await Task.sleep(for: duration)
            guard !Task.isCancelled, self?.activity?.id == newActivity.id else { return }
            self?.activity = nil
        }
    }

    static func read() -> BatteryReading? {
        guard let info = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let sources = IOPSCopyPowerSourcesList(info)?.takeRetainedValue() as? [CFTypeRef]
        else { return nil }
        for source in sources {
            guard let description = IOPSGetPowerSourceDescription(info, source)?.takeUnretainedValue() as? [String: Any],
                  description[kIOPSTypeKey] as? String == kIOPSInternalBatteryType,
                  let current = description[kIOPSCurrentCapacityKey] as? Int,
                  let max = description[kIOPSMaxCapacityKey] as? Int, max > 0
            else { continue }
            let charging = description[kIOPSIsChargingKey] as? Bool ?? false
            let minutes = description[charging ? kIOPSTimeToFullChargeKey : kIOPSTimeToEmptyKey] as? Int
            return BatteryReading(
                percent: Int((Double(current) / Double(max) * 100).rounded()),
                isCharging: charging,
                isPluggedIn: description[kIOPSPowerSourceStateKey] as? String == kIOPSACPowerValue,
                isCharged: description[kIOPSIsChargedKey] as? Bool ?? false,
                minutesRemaining: minutes.flatMap { $0 > 0 ? $0 : nil }
            )
        }
        return nil
    }

    static func symbol(for reading: BatteryReading) -> String {
        if reading.isCharging { return "battery.100.bolt" }
        switch reading.percent {
        case ..<13: return "battery.0"
        case ..<38: return "battery.25"
        case ..<63: return "battery.50"
        case ..<88: return "battery.75"
        default: return "battery.100"
        }
    }

    static func tint(for reading: BatteryReading) -> Color {
        if reading.isPluggedIn { return ChargingStyle.green }
        if reading.percent <= Self.lowThreshold { return Color(red: 1, green: 0.27, blue: 0.23) }
        return .white
    }

    // MARK: Views

    func compactOverlay() -> AnyView? {
        activity?.id == Self.pluggedInActivity ? AnyView(EnergyFlow()) : nil
    }

    /// Sneak peek: the battery level, always.
    var restingActivity: Activity? {
        reading == nil ? nil : Activity(id: "resting", moduleID: id, priority: .background, startedAt: .distantPast)
    }

    func compactLeading() -> AnyView {
        if activity?.id == Self.pluggedInActivity {
            return AnyView(ChargingLeading(isCharging: reading?.isCharging ?? true))
        }
        return AnyView(
            BatteryGlyph(
                level: Double(reading?.percent ?? 0) / 100,
                width: 25,
                fill: reading.map(Self.tint(for:)) ?? .white,
                showsBolt: reading?.isPluggedIn == true,
                glow: 0.2
            )
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.leading, 8)
        )
    }

    func compactTrailing() -> AnyView {
        if activity?.id == Self.pluggedInActivity, let reading {
            return AnyView(ChargingTrailing(percent: reading.percent))
        }
        return AnyView(
            Text(reading.map { "\($0.percent)%" } ?? "")
                .font(.system(size: 13.5, weight: .bold))
                .monospacedDigit()
                .foregroundStyle(reading.map(Self.tint(for:)) ?? .white)
                .contentTransition(.numericText())
                .frame(maxWidth: .infinity, alignment: .trailing)
                .padding(.trailing, 8)
        )
    }

    func expanded() -> AnyView {
        AnyView(BatteryExpandedView(module: self))
    }

    func settings() -> AnyView? {
        AnyView(BatterySettingsView())
    }
}

private struct BatteryExpandedView: View {
    let module: BatteryModule
    @State private var shownLevel = 0.0

    /// The AirPods or headphones to show, if the AirPods module is on and
    /// something is connected: the one that just arrived, else one with a battery.
    private var accessory: AudioAccessory? {
        guard let devices = module.devices, Preferences.shared.isEnabled(devices.id) else { return nil }
        return devices.arrived.flatMap { arrived in devices.accessories.first { $0.name == arrived.name } ?? arrived }
            ?? devices.accessories.first(where: \.hasBattery)
    }

    var body: some View {
        if let reading = module.reading {
            HStack(spacing: accessory == nil ? 26 : 18) {
                BatteryGlyph(
                    level: shownLevel,
                    width: accessory == nil ? 118 : 92,
                    fill: Self.fill(for: reading),
                    showsBolt: reading.isPluggedIn,
                    glow: Self.fill(for: reading) == .white ? 0.12 : 0.5
                )
                .animation(.spring(response: 0.6, dampingFraction: 0.8), value: shownLevel)
                .animation(.spring(response: 0.35, dampingFraction: 0.7), value: reading.isPluggedIn)

                VStack(alignment: .leading, spacing: 6) {
                    HStack(alignment: .firstTextBaseline, spacing: 1) {
                        Text("\(reading.percent)")
                            .font(.system(size: 46, weight: .bold, design: .rounded))
                            .monospacedDigit()
                            .contentTransition(.numericText(value: Double(reading.percent)))
                        Text("%")
                            .font(.system(size: 24, weight: .bold, design: .rounded))
                            .foregroundStyle(.white.opacity(0.6))
                    }
                    Label(Self.status(for: reading), systemImage: Self.statusSymbol(for: reading))
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Self.fill(for: reading) == .white ? .white.opacity(0.85) : Self.fill(for: reading))
                    if let time = Self.timeText(for: reading) {
                        Text(time)
                            .font(.system(size: 12.5, weight: .medium).monospacedDigit())
                            .foregroundStyle(.white.opacity(0.5))
                            .contentTransition(.opacity)
                    } else if Self.isEstimating(reading) {
                        // macOS needs a minute after a change in power to estimate.
                        Text(reading.isCharging ? "Estimating time until full…" : "Estimating time left…")
                            .font(.system(size: 12.5, weight: .medium))
                            .foregroundStyle(.white.opacity(0.5))
                            .phaseAnimator([1.0, 0.45]) { view, opacity in
                                view.opacity(opacity)
                            } animation: { _ in .easeInOut(duration: 0.9) }
                    }
                }
                Spacer(minLength: 0)
                if let accessory {
                    Rectangle()
                        .fill(.white.opacity(0.1))
                        .frame(width: 1, height: 96)
                    AccessoryBatteries(accessory: accessory)
                        .transition(.opacity.combined(with: .move(edge: .trailing)))
                }
            }
            .padding(.leading, 12)
            .animation(.spring(response: 0.4, dampingFraction: 0.85), value: accessory)
            .task { await module.devices?.refresh() }
            .onAppear { shownLevel = Double(reading.percent) / 100 }
            .onChange(of: reading.percent) { _, percent in shownLevel = Double(percent) / 100 }
        } else {
            Text("No battery found")
                .foregroundStyle(.secondary)
        }
    }

    static func fill(for reading: BatteryReading) -> Color {
        if reading.isPluggedIn { return ChargingStyle.green }
        if reading.percent <= BatteryModule.lowThreshold { return Color(red: 1, green: 0.27, blue: 0.23) }
        return .white
    }

    static func status(for reading: BatteryReading) -> String {
        if reading.isCharging { return "Charging" }
        if reading.isPluggedIn { return reading.isCharged ? "Fully charged" : "Not charging" }
        return reading.percent <= BatteryModule.lowThreshold ? "Low battery" : "On battery"
    }

    static func statusSymbol(for reading: BatteryReading) -> String {
        if reading.isCharging { return "bolt.fill" }
        if reading.isPluggedIn { return "powerplug.fill" }
        return reading.percent <= BatteryModule.lowThreshold ? "exclamationmark.triangle.fill" : "laptopcomputer"
    }

    /// A time applies (charging, or on battery) but macOS has none yet.
    static func isEstimating(_ reading: BatteryReading) -> Bool {
        reading.minutesRemaining == nil && (reading.isCharging || !reading.isPluggedIn)
    }

    static func timeText(for reading: BatteryReading) -> String? {
        guard let minutes = reading.minutesRemaining else { return nil }
        let time = minutes >= 60 ? "\(minutes / 60) h \(minutes % 60) min" : "\(minutes) min"
        return reading.isCharging ? "\(time) until full" : "\(time) left"
    }
}

/// IOKit calls this on the main run loop whenever a power source changes.
private nonisolated func powerSourcesChanged(_ context: UnsafeMutableRawPointer?) {
    guard let context else { return }
    let module = Unmanaged<BatteryModule>.fromOpaque(context).takeUnretainedValue()
    MainActor.assumeIsolated { module.refresh() }
}

private struct BatterySettingsView: View {
    @Bindable private var preferences = Preferences.shared

    var body: some View {
        VStack(spacing: 0) {
            SettingRow("Show when power connects") {
                Toggle("", isOn: $preferences.batteryShowOnPlugIn)
            }
            SettingRow("Low battery warning", hint: "The notch stays lit below this level.", last: true) {
                HStack(spacing: 10) {
                    Slider(value: Binding(
                        get: { Double(preferences.batteryLowThreshold) },
                        set: { preferences.batteryLowThreshold = Int($0) }
                    ).snapped(to: 5), in: 5...30)
                    .frame(width: 130)
                    Text("\(preferences.batteryLowThreshold)%")
                        .font(.system(size: 12, weight: .medium).monospacedDigit())
                        .foregroundStyle(SettingsStyle.secondary)
                        .frame(width: 32, alignment: .trailing)
                }
            }
        }
        .toggleStyle(.switch)
        .controlSize(.small)
    }
}
