import Foundation
import SwiftUI
import Testing
@testable import Perch

struct BluetoothReportTests {
    @Test func readsAirPodsBatteriesFromTheSystemReport() {
        let json = """
        {"SPBluetoothDataType":[{"device_connected":[{"AirPods Pro van Dion":{
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

struct AccessoryPowerSourcesTests {
    /// What macOS reports with the right bud charging in a closed case.
    private let sources: [[String: Any]] = [
        ["Name": "AirPods Pro van Dion-case", "Part Identifier": "Case", "Current Capacity": 71,
         "Is Charging": false, "Group Identifier": "G1", "Accessory Category": "Audio Battery Case"],
        ["Name": "AirPods Pro van Dion", "Part Identifier": "Left", "Current Capacity": 65,
         "Is Charging": false, "Group Identifier": "G1", "Product ID": 8231, "Accessory Category": "Headset"],
        ["Name": "AirPods Pro van Dion", "Part Identifier": "Right", "Current Capacity": 64,
         "Is Charging": true, "Group Identifier": "G1", "Product ID": 8231, "Accessory Category": "Headset"],
    ]

    @Test func groupsBudsAndCaseIntoOneAccessory() throws {
        let accessories = AccessoryPowerSources.parse(sources)
        #expect(accessories.count == 1)
        let pods = try #require(accessories.first)
        #expect(pods.name == "AirPods Pro van Dion")
        #expect(pods.kind == .airPodsPro)
        #expect(pods.left == 65 && pods.right == 64 && pods.caseLevel == 71)
        #expect(pods.rightCharging && !pods.leftCharging && !pods.caseCharging)
        #expect(pods.productID == 0x2027)
    }

    @Test func combinedSourceIsSplitIntoBuds() throws {
        let combined: [[String: Any]] = [
            ["Name": "AirPods Pro van Dion-case", "Part Identifier": "Case", "Current Capacity": 70, "Group Identifier": "G1"],
            ["Name": "AirPods Pro van Dion", "Part Identifier": "Combined", "Current Capacity": 65, "Group Identifier": "G1",
             "Combined Parts": [
                ["Name": "AirPods Pro van Dion", "Part Identifier": "Left", "Current Capacity": 65, "Group Identifier": "G1"],
                ["Name": "AirPods Pro van Dion", "Part Identifier": "Right", "Current Capacity": 66, "Group Identifier": "G1"],
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
