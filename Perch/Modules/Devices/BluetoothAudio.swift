import CoreAudio
import Foundation
import IOKit.ps

/// A Bluetooth audio device and its battery, as macOS reports it.
nonisolated struct AudioAccessory: Equatable, Identifiable, Sendable {
    var name: String
    var kind: Kind
    var left: Int?
    var right: Int?
    var caseLevel: Int?
    /// One level for devices without separate buds (AirPods Max, most headphones).
    var single: Int?
    var productID: UInt16?
    /// Which part is charging. A bud only charges in its case, so this also
    /// tells which bud is in the case, even with the lid closed.
    var leftCharging = false
    var rightCharging = false
    var caseCharging = false
    var singleCharging = false

    var id: String { name }

    enum Kind: String, Sendable {
        case airPodsPro, airPodsMax, airPods, beats, headphones, speaker

        var symbol: String {
            switch self {
            case .airPodsPro: "airpods.pro"
            case .airPodsMax: "airpods.max"
            case .airPods: "airpods"
            case .beats: "beats.headphones"
            case .headphones: "headphones"
            case .speaker: "hifispeaker.fill"
            }
        }

        static func guess(name: String, minorType: String?) -> Kind {
            let lower = name.lowercased()
            if lower.contains("airpods max") { return .airPodsMax }
            if lower.contains("airpods pro") { return .airPodsPro }
            if lower.contains("airpods") { return .airPods }
            if lower.contains("beats") { return .beats }
            if minorType?.lowercased().contains("speaker") == true { return .speaker }
            return .headphones
        }
    }

    /// The level to show when there is room for one number: the emptier bud.
    var headline: Int? {
        switch (left, right) {
        case let (l?, r?): min(l, r)
        case let (l?, nil): l
        case let (nil, r?): r
        default: single
        }
    }

    var hasBattery: Bool { headline != nil || caseLevel != nil }
}

/// Reads accessory batteries the way the macOS Batteries widget does: every
/// AirPod, case and headset is a power source of its own, with its exact level
/// and whether it is charging, even inside a closed case. The call is
/// `IOPSCopyPowerSourcesByType`, which `pmset -g accps` uses; IOKit exports it
/// but leaves it out of the public headers, so it is looked up at runtime and
/// Perch falls back to the system report if it ever disappears.
nonisolated enum AccessoryPowerSources {
    /// `kIOPSSourceForAccessories` in IOKit's private header.
    private static let accessoriesType: Int32 = 4

    static func read() -> [AudioAccessory]? {
        typealias ByType = @convention(c) (Int32) -> Unmanaged<CFTypeRef>?
        guard let symbol = dlsym(UnsafeMutableRawPointer(bitPattern: -2), "IOPSCopyPowerSourcesByType") else { return nil }
        let copy = unsafeBitCast(symbol, to: ByType.self)
        guard let info = copy(accessoriesType)?.takeRetainedValue(),
              let list = IOPSCopyPowerSourcesList(info)?.takeRetainedValue() as? [CFTypeRef]
        else { return nil }
        let descriptions = list.compactMap {
            IOPSGetPowerSourceDescription(info, $0)?.takeUnretainedValue() as? [String: Any]
        }
        return parse(descriptions)
    }

    /// Groups the power sources of one device (two buds and a case share a
    /// Group Identifier) into one accessory.
    static func parse(_ sources: [[String: Any]]) -> [AudioAccessory] {
        var order: [String] = []
        var groups: [String: AudioAccessory] = [:]
        // With both buds out of the case macOS merges them into one "Combined"
        // source; the separate buds are inside it.
        let flattened = sources.flatMap { source -> [[String: Any]] in
            if let parts = source["Combined Parts"] as? [[String: Any]], !parts.isEmpty { return parts }
            return [source]
        }
        for source in flattened {
            guard let rawName = source["Name"] as? String,
                  let level = source["Current Capacity"] as? Int else { continue }
            let name = rawName.hasSuffix("-case") ? String(rawName.dropLast(5)) : rawName
            let key = source["Group Identifier"] as? String ?? name
            let charging = source["Is Charging"] as? Bool ?? false
            var accessory = groups[key] ?? AudioAccessory(name: name, kind: .guess(name: name, minorType: source["Accessory Category"] as? String))
            if accessory.productID == nil, let id = source["Product ID"] as? Int { accessory.productID = UInt16(truncatingIfNeeded: id) }
            switch source["Part Identifier"] as? String {
            case "Left": accessory.left = level; accessory.leftCharging = charging
            case "Right": accessory.right = level; accessory.rightCharging = charging
            case "Case": accessory.caseLevel = level; accessory.caseCharging = charging
            default: accessory.single = level; accessory.singleCharging = charging
            }
            if groups[key] == nil { order.append(key) }
            groups[key] = accessory
        }
        return order.compactMap { groups[$0] }
    }
}

/// Fallback: connected Bluetooth accessories and their batteries from
/// `system_profiler -json SPBluetoothDataType`, without charging state.
nonisolated enum BluetoothReport {
    static func parse(_ data: Data) -> [AudioAccessory] {
        guard
            let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let controllers = root["SPBluetoothDataType"] as? [[String: Any]]
        else { return [] }
        var accessories: [AudioAccessory] = []
        for controller in controllers {
            for entry in controller["device_connected"] as? [[String: Any]] ?? [] {
                for (name, value) in entry {
                    guard let info = value as? [String: Any] else { continue }
                    let minor = info["device_minorType"] as? String
                    accessories.append(AudioAccessory(
                        name: name,
                        kind: .guess(name: name, minorType: minor),
                        left: percent(info["device_batteryLevelLeft"]),
                        right: percent(info["device_batteryLevelRight"]),
                        caseLevel: percent(info["device_batteryLevelCase"]),
                        single: percent(info["device_batteryLevelMain"]) ?? percent(info["device_batteryLevel"]),
                        productID: (info["device_productID"] as? String).flatMap { UInt16($0.dropFirst(2), radix: 16) }
                    ))
                }
            }
        }
        return accessories
    }

    private static func percent(_ value: Any?) -> Int? {
        guard let text = value as? String else { return nil }
        return Int(text.trimmingCharacters(in: CharacterSet(charactersIn: "% ")))
    }

    /// Runs the report off the main thread.
    static func read() async -> [AudioAccessory] {
        await Task.detached(priority: .utility) {
            let process = Process()
            process.executableURL = URL(filePath: "/usr/sbin/system_profiler")
            process.arguments = ["-json", "SPBluetoothDataType"]
            let pipe = Pipe()
            process.standardOutput = pipe
            process.standardError = FileHandle.nullDevice
            do { try process.run() } catch { return [] }
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            return parse(data)
        }.value
    }
}

/// Names of the Bluetooth audio devices CoreAudio currently knows, and a
/// callback when that list changes: the moment AirPods connect or leave.
/// CoreAudio needs no permission for this.
final class BluetoothAudioWatcher {
    private var listener: AudioObjectPropertyListenerBlock?
    private var address = AudioObjectPropertyAddress(
        mSelector: kAudioHardwarePropertyDevices,
        mScope: kAudioObjectPropertyScopeGlobal,
        mElement: kAudioObjectPropertyElementMain
    )

    func start(onChange: @escaping @MainActor () -> Void) {
        let block: AudioObjectPropertyListenerBlock = { _, _ in
            Task { @MainActor in onChange() }
        }
        listener = block
        AudioObjectAddPropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject), &address, .main, block)
    }

    func stop() {
        guard let listener else { return }
        AudioObjectRemovePropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject), &address, .main, listener)
        self.listener = nil
    }

    static func currentNames() -> Set<String> {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size) == noErr else { return [] }
        var ids = [AudioDeviceID](repeating: 0, count: Int(size) / MemoryLayout<AudioDeviceID>.size)
        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &ids) == noErr else { return [] }
        var names: Set<String> = []
        for id in ids where isBluetooth(id) {
            if let name = name(of: id) { names.insert(name) }
        }
        return names
    }

    private static func isBluetooth(_ id: AudioDeviceID) -> Bool {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyTransportType,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var transport: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        guard AudioObjectGetPropertyData(id, &address, 0, nil, &size, &transport) == noErr else { return false }
        return transport == kAudioDeviceTransportTypeBluetooth || transport == kAudioDeviceTransportTypeBluetoothLE
    }

    private static func name(of id: AudioDeviceID) -> String? {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioObjectPropertyName,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var name: Unmanaged<CFString>?
        var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        guard AudioObjectGetPropertyData(id, &address, 0, nil, &size, &name) == noErr, let name else { return nil }
        return name.takeRetainedValue() as String
    }
}
