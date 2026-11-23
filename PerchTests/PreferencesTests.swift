import Foundation
import SwiftUI
import Testing
@testable import Perch

struct PreferencesTests {
    private func freshDefaults() -> UserDefaults {
        let name = "perch.tests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        return defaults
    }

    @Test func defaultsMatchTheTunedValues() {
        let preferences = Preferences(defaults: freshDefaults())
        #expect(preferences.openOnHover)
        #expect(preferences.hoverDelay == 0.3)
        #expect(preferences.hapticStrength == .strong)
        #expect(preferences.displayMode == .notchedScreens)
        #expect(preferences.musicLinger == 6)
        #expect(preferences.batteryLowThreshold == 10)
        #expect(preferences.isEnabled("music"))
        #expect(preferences.hideInFullScreen)
    }

    @Test func changesSurviveARestart() {
        let defaults = freshDefaults()
        let first = Preferences(defaults: defaults)
        first.hoverDelay = 0.5
        first.displayMode = .allScreens
        first.setEnabled(false, for: "battery")
        first.openOnHover = false

        let second = Preferences(defaults: defaults)
        #expect(second.hoverDelay == 0.5)
        #expect(second.displayMode == .allScreens)
        #expect(!second.isEnabled("battery"))
        #expect(second.isEnabled("music"))
        #expect(!second.openOnHover)
    }

    @Test func oldHapticsSwitchCarriesOver() {
        let defaults = freshDefaults()
        defaults.set(false, forKey: Preferences.Key.haptics)
        #expect(Preferences(defaults: defaults).hapticStrength == .off)
    }

    @Test func disabledModulesAreLeftOutOfTheArbiter() {
        let preferences = Preferences(defaults: freshDefaults())
        let module = StubModule(id: "stub")
        module.activity = Activity(id: "a", moduleID: "stub", priority: .urgent)
        let host = ModuleHost(modules: [module], preferences: preferences)
        #expect(host.current?.id == "a")
        preferences.setEnabled(false, for: "stub")
        #expect(host.current == nil)
        #expect(host.module(id: "stub") == nil)
    }
}

private final class StubModule: PerchModule {
    let id: String
    let title = "Stub"
    let symbol = "circle"
    let summary = ""
    var activity: Activity?
    init(id: String) { self.id = id }
    func start() {}
    func stop() {}
    func compactLeading() -> AnyView { AnyView(EmptyView()) }
    func compactTrailing() -> AnyView { AnyView(EmptyView()) }
    func expanded() -> AnyView { AnyView(EmptyView()) }
}
