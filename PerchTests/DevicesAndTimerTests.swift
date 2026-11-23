import Foundation
import SwiftUI
import Testing
@testable import Perch

struct BluetoothReportTests {
    @Test func readsAirPodsBatteriesFromTheSystemReport() {
        let json = """
        {"SPBluetoothDataType":[{"device_connected":[{"Sam's AirPods Pro":{
          "device_batteryLevelCase":"71%","device_batteryLevelLeft":"70%",
          "device_batteryLevelRight":"65%","device_minorType":"Headphones"}}]}]}
        """
        let accessories = BluetoothReport.parse(Data(json.utf8))
        #expect(accessories.count == 1)
        let pods = accessories[0]
        #expect(pods.kind == .airPodsPro)
        #expect(pods.left == 70 && pods.right == 65 && pods.caseLevel == 71)
        #expect(pods.headline == 65)
    }

    @Test func headphonesWithOneLevelUseIt() {
        let json = """
        {"SPBluetoothDataType":[{"device_connected":[{"WH-1000XM5":{
          "device_batteryLevelMain":"40%","device_minorType":"Headphones"}}]}]}
        """
        let accessory = BluetoothReport.parse(Data(json.utf8)).first
        #expect(accessory?.kind == .headphones)
        #expect(accessory?.headline == 40)
    }

    @Test func noConnectedDevicesIsEmpty() {
        #expect(BluetoothReport.parse(Data(#"{"SPBluetoothDataType":[{}]}"#.utf8)).isEmpty)
        #expect(BluetoothReport.parse(Data("junk".utf8)).isEmpty)
    }
}

struct TimerFormatTests {
    @Test func formatsMinutesAndHours() {
        #expect(TimerStyle.format(65) == "1:05")
        #expect(TimerStyle.format(0.2) == "0:01")
        #expect(TimerStyle.format(3600) == "1:00:00")
    }
}

struct SneakPeekTests {
    @Test func restingModuleFillsTheNotchOnlyWhenNothingElseDoes() {
        let defaults = UserDefaults(suiteName: "perch.tests.\(UUID().uuidString)")!
        let preferences = Preferences(defaults: defaults)
        let resting = RestingStub(id: "music")
        let host = ModuleHost(modules: [resting], preferences: preferences)
        #expect(host.current == nil)

        preferences.restingModule = "music"
        #expect(host.current?.id == "resting")

        resting.activity = Activity(id: "live", moduleID: "music", priority: .info)
        #expect(host.current?.id == "live")
    }
}

private final class RestingStub: PerchModule {
    let id: String
    let title = "Stub"
    let symbol = "circle"
    let summary = ""
    var activity: Activity?
    var restingActivity: Activity? { Activity(id: "resting", moduleID: id, priority: .background, startedAt: .distantPast) }
    init(id: String) { self.id = id }
    func start() {}
    func stop() {}
    func compactLeading() -> AnyView { AnyView(EmptyView()) }
    func compactTrailing() -> AnyView { AnyView(EmptyView()) }
    func expanded() -> AnyView { AnyView(EmptyView()) }
}

struct AirPodsMomentTests {
    private let charging = AudioAccessory(name: "Pods", kind: .airPodsPro, left: 60, right: 60, caseLevel: 70,
                                          leftCharging: true, rightCharging: true)

    @Test func takingBudsOutOfTheCaseIsTheMoment() {
        var out = charging
        out.leftCharging = false
        out.rightCharging = false
        #expect(DevicesModule.arrival(from: [charging], to: [out])?.name == "Pods")
    }

    @Test func newlyConnectedAirPodsAreTheMoment() {
        #expect(DevicesModule.arrival(from: [], to: [charging])?.name == "Pods")
    }

    @Test func batteryTicksAreNotAMoment() {
        var tick = charging
        tick.caseLevel = 69
        #expect(DevicesModule.arrival(from: [charging], to: [tick]) == nil)
        var putBack = charging
        putBack.leftCharging = true
        #expect(DevicesModule.arrival(from: [charging], to: [putBack]) == nil)
    }
}

struct AccessoryPowerSourcesTests {
    /// What macOS reports with the right bud charging in a closed case.
    private let sources: [[String: Any]] = [
        ["Name": "Sam's AirPods Pro-case", "Part Identifier": "Case", "Current Capacity": 71,
         "Is Charging": false, "Group Identifier": "G1", "Accessory Category": "Audio Battery Case"],
        ["Name": "Sam's AirPods Pro", "Part Identifier": "Left", "Current Capacity": 65,
         "Is Charging": false, "Group Identifier": "G1", "Product ID": 8231, "Accessory Category": "Headset"],
        ["Name": "Sam's AirPods Pro", "Part Identifier": "Right", "Current Capacity": 64,
         "Is Charging": true, "Group Identifier": "G1", "Product ID": 8231, "Accessory Category": "Headset"],
    ]

    @Test func groupsBudsAndCaseIntoOneAccessory() throws {
        let accessories = AccessoryPowerSources.parse(sources)
        #expect(accessories.count == 1)
        let pods = try #require(accessories.first)
        #expect(pods.name == "Sam's AirPods Pro")
        #expect(pods.kind == .airPodsPro)
        #expect(pods.left == 65 && pods.right == 64 && pods.caseLevel == 71)
        #expect(pods.rightCharging && !pods.leftCharging && !pods.caseCharging)
        #expect(pods.productID == 0x2027)
    }

    @Test func combinedSourceIsSplitIntoBuds() throws {
        let combined: [[String: Any]] = [
            ["Name": "Sam's AirPods Pro-case", "Part Identifier": "Case", "Current Capacity": 70, "Group Identifier": "G1"],
            ["Name": "Sam's AirPods Pro", "Part Identifier": "Combined", "Current Capacity": 65, "Group Identifier": "G1",
             "Combined Parts": [
                ["Name": "Sam's AirPods Pro", "Part Identifier": "Left", "Current Capacity": 65, "Group Identifier": "G1"],
                ["Name": "Sam's AirPods Pro", "Part Identifier": "Right", "Current Capacity": 66, "Group Identifier": "G1"],
             ]],
        ]
        let pods = try #require(AccessoryPowerSources.parse(combined).first)
        #expect(pods.left == 65 && pods.right == 66 && pods.caseLevel == 70)
        #expect(pods.single == nil)
    }

    @Test func headsetWithOneBatteryUsesSingle() {
        let headset = AccessoryPowerSources.parse([["Name": "WH-1000XM5", "Current Capacity": 40, "Is Charging": true]])
        #expect(headset.first?.single == 40)
        #expect(headset.first?.singleCharging == true)
    }
}

struct MediaKeyTests {
    @Test func decodesVolumeAndBrightnessKeys() {
        // NX_KEYTYPE_SOUND_UP (0) pressed: code in the high half, 0xA in the state byte.
        #expect(MediaKey.decode(subtype: 8, data1: (0 << 16) | 0x0A00)?.key == .volumeUp)
        #expect(MediaKey.decode(subtype: 8, data1: (0 << 16) | 0x0A00)?.isDown == true)
        #expect(MediaKey.decode(subtype: 8, data1: (3 << 16) | 0x0B00)?.key == .brightnessDown)
        #expect(MediaKey.decode(subtype: 8, data1: (3 << 16) | 0x0B00)?.isDown == false)
        #expect(MediaKey.decode(subtype: 8, data1: (7 << 16) | 0x0A00)?.key == .mute)
    }

    @Test func otherKeysPassThrough() {
        // Play/pause (16) and other subtypes are not Perch's.
        #expect(MediaKey.decode(subtype: 8, data1: (16 << 16) | 0x0A00) == nil)
        #expect(MediaKey.decode(subtype: 7, data1: (0 << 16) | 0x0A00) == nil)
    }
}

struct SwipeTrackerTests {
    @Test func clearDownwardMovementIsOneSwipeDown() {
        var tracker = SwipeTracker()
        #expect(tracker.add(dx: 0, dy: 20) == nil)
        #expect(tracker.add(dx: 2, dy: 20) == .down)
        // The rest of the same movement does not fire again.
        #expect(tracker.add(dx: 0, dy: 60) == nil)
        tracker.reset()
        #expect(tracker.add(dx: 0, dy: -50) == .up)
    }

    @Test func sidewaysNeedsToDominate() {
        var tracker = SwipeTracker()
        // Diagonal: neither axis clearly wins, so nothing happens yet.
        #expect(tracker.add(dx: 40, dy: 35) == nil)
        tracker.reset()
        #expect(tracker.add(dx: -45, dy: 5) == .left)
        tracker.reset()
        #expect(tracker.add(dx: 45, dy: -5) == .right)
    }

    @Test func smallTwitchesAreIgnored() {
        var tracker = SwipeTracker()
        #expect(tracker.add(dx: 5, dy: 10) == nil)
        #expect(tracker.add(dx: -3, dy: 8) == nil)
    }
}
