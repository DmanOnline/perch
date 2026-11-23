import Foundation
import IOKit.ps
import Observation
import SwiftUI

nonisolated struct BatteryReading: Equatable, Sendable {
    var percent: Int
    var isCharging: Bool
    var isPluggedIn: Bool
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
            return BatteryReading(
                percent: Int((Double(current) / Double(max) * 100).rounded()),
                isCharging: description[kIOPSIsChargingKey] as? Bool ?? false,
                isPluggedIn: description[kIOPSPowerSourceStateKey] as? String == kIOPSACPowerValue
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
        if reading.isPluggedIn { return .green }
        if reading.percent <= Self.lowThreshold { return .red }
        return .white
    }

    // MARK: Views

    func compactOverlay() -> AnyView? {
        activity?.id == Self.pluggedInActivity ? AnyView(EnergyFlow()) : nil
    }

    func compactLeading() -> AnyView {
        if activity?.id == Self.pluggedInActivity {
            return AnyView(ChargingLeading(isCharging: reading?.isCharging ?? true))
        }
        return AnyView(
            Image(systemName: reading?.isPluggedIn == true ? "bolt.fill" : "battery.25")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(reading.map(Self.tint(for:)) ?? .white)
        )
    }

    func compactTrailing() -> AnyView {
        if activity?.id == Self.pluggedInActivity, let reading {
            return AnyView(ChargingTrailing(percent: reading.percent))
        }
        return AnyView(
            Text(reading.map { "\($0.percent)%" } ?? "")
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(reading.map(Self.tint(for:)) ?? .white)
                .contentTransition(.numericText())
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

    var body: some View {
        if let reading = module.reading {
            HStack(spacing: 18) {
                Image(systemName: BatteryModule.symbol(for: reading))
                    .font(.system(size: 46, weight: .regular))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(BatteryModule.tint(for: reading))
                VStack(alignment: .leading, spacing: 4) {
                    Text("\(reading.percent)%")
                        .font(.system(size: 34, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                        .contentTransition(.numericText())
                    Text(reading.isCharging ? "Charging" : reading.isPluggedIn ? "Connected to power" : "On battery")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }
        } else {
            Text("No battery found")
                .foregroundStyle(.secondary)
        }
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
