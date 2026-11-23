import Observation
import SwiftUI

/// AirPods and other Bluetooth audio. When they connect they slide out of the
/// notch with their battery, the way an iPhone shows them; the tab shows each
/// bud and the case.
@Observable
final class DevicesModule: PerchModule {
    static let connectedDisplay: Duration = .seconds(5)

    let id = "devices"
    let title = "AirPods"
    let summary = "AirPods and headphones slide out of the notch when they connect; their batteries live in the Battery tab."
    /// No tab of its own: the batteries sit in the Battery tab.
    let tabID = "battery"
    var symbol: String { accessories.first?.kind.symbol ?? "airpods.pro" }

    private(set) var accessories: [AudioAccessory] = []
    private(set) var activity: Activity?
    /// The accessory whose arrival holds the notch.
    private(set) var arrived: AudioAccessory?

    @ObservationIgnored private let watcher = BluetoothAudioWatcher()
    @ObservationIgnored private var knownNames: Set<String> = []
    @ObservationIgnored private var refreshTask: Task<Void, Never>?
    @ObservationIgnored private var clearTask: Task<Void, Never>?
    @ObservationIgnored private var debugObserver: NSObjectProtocol?
    @ObservationIgnored private var powerSource: CFRunLoopSource?

    func start() {
        knownNames = BluetoothAudioWatcher.currentNames()
        watcher.start { [weak self] in self?.audioDevicesChanged() }
        followPowerSources()
        Task { await refresh() }
        #if DEBUG
        // Replays a connection for tuning and screenshots:
        // post the distributed notification "app.perch.debug.airpods".
        debugObserver = DistributedNotificationCenter.default().addObserver(
            forName: Notification.Name("app.perch.debug.airpods"), object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.announce(AudioAccessory(name: "AirPods Pro", kind: .airPodsPro, left: 82, right: 79, caseLevel: 64))
            }
        }
        #endif
    }

    func stop() {
        watcher.stop()
        if let powerSource { CFRunLoopRemoveSource(CFRunLoopGetMain(), powerSource, .commonModes) }
        powerSource = nil
        refreshTask?.cancel()
        clearTask?.cancel()
    }

    /// Re-reads batteries, for example when the tab opens.
    /// Re-reads batteries: from macOS's accessory power sources, which know
    /// what is charging; devices only the system report knows are added after.
    func refresh() async {
        let power = AccessoryPowerSources.read() ?? []
        let report = await BluetoothReport.read()
        let known = Set(power.map(\.name))
        accessories = power + report.filter { !known.contains($0.name) }
        if let current = arrived, let updated = accessories.first(where: { $0.name == current.name }) {
            arrived = updated
        }
    }

    /// Batteries change, buds go in and out of the case: macOS posts each one
    /// as a power source change.
    private func followPowerSources() {
        let context = Unmanaged.passUnretained(self).toOpaque()
        guard let source = IOPSNotificationCreateRunLoopSource(accessoryPowerChanged, context)?.takeRetainedValue() else { return }
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        powerSource = source
    }

    private func audioDevicesChanged() {
        let names = BluetoothAudioWatcher.currentNames()
        let new = names.subtracting(knownNames)
        knownNames = names
        guard let name = new.first else {
            Task { await refresh() }
            return
        }
        // The battery reaches macOS a moment after the connection; ask a few times.
        refreshTask?.cancel()
        refreshTask = Task { [weak self] in
            for delay in [0.3, 1.5, 3.0] {
                try? await Task.sleep(for: .seconds(delay))
                guard !Task.isCancelled, let self else { return }
                await self.refresh()
                if let found = self.accessories.first(where: { $0.name == name }) {
                    if self.arrived?.name != name { self.announce(found) }
                    if found.hasBattery { return }
                }
            }
        }
    }

    private func announce(_ accessory: AudioAccessory) {
        arrived = accessory
        Haptics.play(.event)
        clearTask?.cancel()
        let shown = Activity(id: "connected", moduleID: id, priority: .attention, expiresAt: .now + 5)
        activity = shown
        clearTask = Task { [weak self] in
            try? await Task.sleep(for: Self.connectedDisplay)
            guard !Task.isCancelled, self?.activity?.id == shown.id else { return }
            self?.activity = nil
        }
    }

    // MARK: Views

    func compactLeading() -> AnyView {
        AnyView(
            Image(systemName: arrived?.kind.symbol ?? symbol)
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(.white)
                .symbolEffect(.bounce, value: arrived?.name)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.leading, 8)
        )
    }

    func compactTrailing() -> AnyView {
        AnyView(
            HStack(spacing: 5) {
                if let level = arrived?.headline {
                    Text("\(level)%")
                        .font(.system(size: 13.5, weight: .bold))
                        .monospacedDigit()
                        .foregroundStyle(DeviceStyle.color(for: level))
                    BatteryRing(level: level, size: 17, lineWidth: 2.6)
                }
            }
            .frame(maxWidth: .infinity, alignment: .trailing)
            .padding(.trailing, 6)
        )
    }

    func expanded() -> AnyView {
        AnyView(EmptyView())
    }
}

enum DeviceStyle {
    static func color(for level: Int) -> Color {
        level <= 20 ? Color(red: 1, green: 0.27, blue: 0.23) : ChargingStyle.green
    }
}

/// A ring that fills with the battery level, green, red when low.
struct BatteryRing: View {
    let level: Int
    var size: CGFloat = 46
    var lineWidth: CGFloat = 5

    var body: some View {
        ZStack {
            Circle().stroke(.white.opacity(0.15), lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: CGFloat(level) / 100)
                .stroke(DeviceStyle.color(for: level), style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .animation(.spring(response: 0.6, dampingFraction: 0.85), value: level)
        }
        .frame(width: size, height: size)
    }
}

/// One accessory in the Battery tab: icon and name, then a ring per bud and
/// the case.
struct AccessoryBatteries: View {
    let accessory: AudioAccessory

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 7) {
                Image(systemName: accessory.kind.symbol)
                    .font(.system(size: 17, weight: .medium))
                Text(accessory.name)
                    .font(.system(size: 12.5, weight: .semibold))
                    .lineLimit(1)
            }
            .foregroundStyle(.white.opacity(0.85))

            HStack(spacing: 12) {
                if accessory.left != nil || accessory.right != nil {
                    gauge("L", accessory.left, charging: accessory.leftCharging)
                    gauge("R", accessory.right, charging: accessory.rightCharging)
                } else if let single = accessory.single {
                    gauge("", single, charging: accessory.singleCharging)
                }
                if let caseLevel = accessory.caseLevel {
                    gauge("Case", caseLevel, charging: accessory.caseCharging)
                }
                if !accessory.hasBattery {
                    Text("Battery not reported yet")
                        .font(.system(size: 12))
                        .foregroundStyle(.white.opacity(0.5))
                }
            }
        }
    }

    /// A ring with the level; a charging part gets a green bolt beside its label.
    private func gauge(_ label: String, _ level: Int?, charging: Bool) -> some View {
        VStack(spacing: 4) {
            ZStack {
                BatteryRing(level: level ?? 0, size: 40, lineWidth: 4)
                Text(level.map { "\($0)" } ?? "–")
                    .font(.system(size: 12.5, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(.white)
            }
            HStack(spacing: 2) {
                if charging {
                    Image(systemName: "bolt.fill")
                        .font(.system(size: 9, weight: .black))
                        .foregroundStyle(ChargingStyle.green)
                        .transition(.scale.combined(with: .opacity))
                }
                if !label.isEmpty {
                    Text(label)
                        .font(.system(size: 10.5, weight: .semibold))
                        .foregroundStyle(charging ? ChargingStyle.green : .white.opacity(0.55))
                }
            }
            .animation(.spring(response: 0.3, dampingFraction: 0.7), value: charging)
        }
    }
}

/// IOKit calls this on the main run loop whenever a power source changes.
private nonisolated func accessoryPowerChanged(_ context: UnsafeMutableRawPointer?) {
    guard let context else { return }
    let module = Unmanaged<DevicesModule>.fromOpaque(context).takeUnretainedValue()
    MainActor.assumeIsolated { _ = Task { await module.refresh() } }
}
